EventEmitter = require('events').EventEmitter
Mongo = require 'mongoskin'
Promise = require 'promise'
class StormRegistryData

    validate = require('json-schema').validate

    # every registry data has a schema to enforce - to be subclassed

    validate: ->
        return true unless @data? and @schema?
        res = validate @data, @schema
        res.valid

    serialize: ->
        JSON.stringify @data

#---------------------------------------------------------------------------------------------------------
class MongoRegistry extends EventEmitter
    constructor: (opts) ->
        @url = opts.url
        # Mongo.db(@url,native_parser:true)
        @db = opts.db
        @collection = opts.collection
        @emit 'ready'
    add: (key, entry) ->
        new Promise (fullfill, reject) =>
            @db.collection(@collection).insert entry, (err, result)->
                if err?
                    reject(err)
                else
                    if result.length>0
                        fullfill(result[0])
                    else
                        fullfill(result)

                    @emit 'added', entry

    #search for one result
    get: (key) ->
        new Promise (fullfill,reject) =>
            @db.collection(@collection).findOne key ,(err,result) =>
                if err?
                    reject(err)
                else
                    fullfill(result)

    #find one or more records
    find: (key) ->
        new Promise (fullfill,reject) =>
            @db.collection(@collection).find key, (err,result) =>
                if err?
                    reject(err)
                else
                    fullfill(result)

    remove: (key) ->
        new Promise (fullfill, reject) =>
            @db.collection(@collection).remove key, (err,result) =>
                if err?
                    reject(err)
                else
                    fullfill(result)

    update: (key,entry,suppress) ->
        new Promise (fullfill, reject) =>
            @db.collection(@collection).update key,entry, (err,result) =>
                if err?
                    reject(err)
                else
                    fullfill(result)
                    @emit 'updated', entry,entry.dirtyProperties unless suppress is true

    list: () ->
        new Promise (fullfill, reject) =>
            @db.collection(@collection).find {}, (err,result) =>
                if err?
                    reject(err)
                else
                    fullfill(result)


class StormRegistry extends EventEmitter

    uuid = require('node-uuid')
    async = require 'async'
    bunyan = require 'bunyan'

    constructor: (opts) ->
        if opts? and opts instanceof Object
            @log = opts.log?.child class: @constructor.name
            filename = opts.path
        else
            # backwards-compatibility
            filename = opts

        @log ?= new bunyan name: @constructor.name

        @running = true
        @entries = {}

        if filename
            @db = require('dirty') "#{filename}"
            @db.on 'load', =>
                @log.info method:'load',path:filename, "loading a registry from a persistent db"
                try
                    @db.forEach (key,val) =>
                        @log.debug method:'load',key:key, "found a record, issuing load event handler"
                        @emit 'load', key, val if val?
                catch err
                    @log.error err, "issue during processing the db file at #{filename}"
                @emit 'ready'
            @db._writeStream.on 'error', (err) =>
                @log.error err, 'failed to open file for writing'
        else
            process.nextTick => @emit 'ready'

    getKey: (key) ->
        return unless key? and @entries.hasOwnProperty(key)
        @entries[key]

    add: (key, entry) ->
        return unless entry?
        if @getKey key
            return @update key, entry, true

        key ?= uuid.v4() # if no key provided, dynamically generate one
        entry.id ?= key
        entry.saved ?= false
        @log.debug method:'add',key:key, "adding a new entry"
        if @db? and not entry.saved
            data = switch
                when entry instanceof StormRegistryData then entry.serialize tag:true
                else entry
            @log.debug method:'add',key:key, "saving entry into persistent db"
            try
                @db.set key, data
                entry.saved = true
            catch err
                @log.error error:err,data:data, "failed to save the provided data record"
        @entries[key] = entry
        @emit 'added', entry
        entry

    get: (key) ->
        return unless key? and @entries.hasOwnProperty(key)
        @entries[key]

    remove: (key) ->
        return unless key?
        @log.debug method:'remove',key:key, "removing an entry"
        entry = @entries[key]
        # delete the key from obj first...
        delete @entries[key]
        @emit 'removed', entry if entry?
        # check if data-backend and there is an entry that's been saved
        if @db? and entry? and entry.saved
            @db.rm key

    update: (key, entry, suppress) ->
        return unless key? and entry?
        @log.debug method:'update',key:key, "updating an entry"
        if @db? and (not entry.saved or entry.changed)
            data = switch
                when entry instanceof StormRegistryData then entry.serialize tag:true
                else entry
            @db.set key, data
            @log.debug method:'update',key:key,data:data, "saved an entry into persistent db"
            entry.saved = true
        @entries[key] = entry
        @emit 'updated', entry unless suppress is true
        entry

    list: -> (@get key for key of @entries).filter (x) -> x?

    checksum: ->
        crypto = require 'crypto' # for checksum capability on registry
        md5 = crypto.createHash "md5"
        md5.update key for key,entry of @entries
        md5.digest "hex"

    expires: (interval,validity) ->
        # initialize validity if not already set
        validity ?= 60 * 60
        for key,entry of @entries
             do (entry) -> entry.validity ?= validity

        async.whilst(
            () => # test condition
                @running
            (repeat) =>
                for key,entry of @entries
                    unless entry?
                        @remove key
                        continue
                    do (key,entry) =>
                        @log.debug "#{key} has validity=#{entry.validity}"
                        @entries[key].validity -= interval / 1000
                        unless @entries[key].validity > 1
                            @remove key
                            @log.info method:'expires',key:key, "entry has expired and removed from registry"
                            @emit "expired", entry
                setTimeout(repeat, interval)
            (err) =>
                @log.warn method:'expires', "registry stopped running, validity checker stopping..."
        )

module.exports.StormRegistry = StormRegistry
module.exports.StormRegistryData = StormRegistryData
module.exports.MongoRegistry = MongoRegistry
