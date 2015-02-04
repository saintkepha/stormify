# mixin = require './mixin'
# DynamicResolver    = require './dynamic-resolver'
# extends mixin DynamicResolver
#
assert = require 'assert'
bunyan = require 'bunyan'

#---------------------------------------------------------------------------------------------------------

SR = require './stormregistry'

#-----------------------------------
# DataStoreRegistry
#
# Uses deferred DataStoreModel instantiation to take place only on @get
#
class DataStoreRegistry extends SR

    constructor: (@collection,opts) ->
        @store = opts?.store
        assert @store? and @store.contains(@collection), "cannot construct DataStoreRegistry without valid store containing '#{collection}' passed in"

        @log = opts?.log?.child class: @constructor.name
        @log ?= new bunyan name: @constructor.name

        @entity = @store.contains(@collection)

        @on 'load', (key,val) ->
            @log.debug entity:@entity.name,key:key,'loading a persisted record'
            entry = val?[@entity.name]
            if entry?
                entry.id = key
                entry.saved = true
                @add key, entry
        @on 'ready', ->
            size = Object.keys(@entries)?.length
            @log.info entity:@entity.name,size:size,"registry for '#{@collection}' initialized with #{size} records"

        super
            log: @log
            path: "#{@store.datadir}/#{@collection}.db" if opts?.persist

    keys: -> Object.keys(@entries)

    get: (id) ->
        entry = super id
        return null unless entry?
        unless entry instanceof DataStoreModel
            @log.debug id:id, "restoring #{@entity.name} from registry using underlying entry"

            # we try here since we don't know if we can successfully createRecord during restoration!
            try
                record = @store.createRecord @entity.name, entry
                record.isSaved = true
                @update id, record, true
            catch err
                @log.warn method:'get',id:id,error:err, "issue while trying to restore a record of '#{@entity.name}' from registry"
                return null

        super id

    # this overrides parent registry.update call to suppress event
    # emit and instead provide additional details (changed properties) with the event
    update: (key, entry, suppress) ->
        super key, entry, true # force suppressing event
        @emit 'updated', entry, entry.dirtyProperties() unless suppress is true
        entry

#---------------------------------------------------------------------------------------------------------

#---------------------------------------------------------------------------------------------------------

EventEmitter = require('events').EventEmitter

class DataStoreController extends EventEmitter

    actions: {} # to be subclassed by controllers

    constructor: (opts) ->
        assert opts? and opts.model instanceof DataStoreModel, "unable to create an instance of DS.Controller without underlying model!"

        # XXX - may change to check for instanceof DataStoreView in the future
        #assert opts? and opts.view  instanceof DataStoreView, "unable to create an instance of DS.Controller without a proper view!"

        @model = opts.model
        @store = @view  = opts.view # hack for now to preserve existing controller behavior

        @log = opts.log?.child class: @constructor.name
        @log ?= new bunyan name: @constructor.name

    beforeUpdate: (data) ->
        @emit 'beforeUpdate', [ @model.name, @model.id ]

    afterUpdate: (data) ->
        @model.set 'modifiedOn', new Date()
        @emit 'afterUpdate', [ @model.name, @model.id ]

    beforeSave: ->
        @emit 'beforeSave', [ @model.name, @model.id ]

        @log.trace method:'beforeSave', 'we should auto resolve belongsTo and hasMany here...'

        createdOn = @model.get 'createdOn'
        unless createdOn?
            @model.set 'createdOn', new Date()
            @model.set 'modifiedOn', new Date()
            @model.set 'accessedOn', new Date()

        # when prop.model? and x instanceof Object
        #     try
        #         inverse = prop.opts?.inverse
        #         x[inverse] = @ if inverse?
        #         record = @store.createRecord prop.model,x
        #         record.save()
        #     catch err
        #         @log.warn error:err, "attempt to auto-create #{prop.model} failed"
        #         record = x
        #     #XXX - why does record.save() hang?
        #     record

    afterSave: ->
        @emit 'afterSave', [ @model.name, @model.id ]

    beforeDestroy: ->
        @emit 'beforeDestroy', [ @model.name, @model.id ]

    afterDestroy: ->
        @log.info method:'afterDestroy', model:@model.name, id:@model.id, 'invoking afterDestroy to remove external references to this model'
        # go through all model relations and remove reference back to the @model
        for key,relation of @model.relations
            @log.debug method:'afterDestroy',key:key,relation:relation,"checking #{key}.#{relation.type} '#{relation.model}'"
            try
                switch relation.type
                    when 'belongsTo' then @model.get(key)?.removeReferences? @model, true
                    when 'hasMany'   then target?.removeReferences? @model, true for target in @model.get(key)
            catch err
                @log.debug method:'afterDestroy',key:key,relation:relation,"ignoring relation to '#{key}' that cannot be resolved"

        @emit 'afterDestroy', [ @model.name, @model.id ]

#---------------------------------------------------------------------------------------------------------

# Wrapper around underlying DataStore
#
# Used during store.open(requestor) in order to provide access context
# for store operations. Also, DataStore sub-classes can override the
# store.open call to manipulate the views into the underlying entities
class DataStoreView

    extend = require('util')._extend

    constructor: (@store, @requestor) ->
        assert store instanceof DataStore, "cannot provide View without valid DataStore"
        @entities = extend {}, @store.entities
        @log = @store.log?.child class: @constructor.name
        @log ?= new bunyan name: @constructor.name

        #@transactions = []

    createRecord: (args...) ->
        record = @store.createRecord.apply @, args
        #@transactions.push create:record
        record

    deleteRecord: (args...) -> @store.deleteRecord.apply @, args
    updateRecord: (args...) -> @store.updateRecord.apply @, args
    findRecord:   (args...) -> @store.findRecord.apply @, args
    findBy:       (args...) -> @store.findBy.apply @, args
    find:         (args...) -> @store.find.apply @, args

#---------------------------------------------------------------------------------------------------------

DataStormModel  = require './data-storm-model'
DataStormRecord = require './data-storm-record'

class DataStorm extends DataStormModel

    # various extensions available from this class object
    @Model      = DataStormModel
    @Record     = DataStormRecord

    @Controller = DataStormController
    @View       = DataStormView
    @Registry   = DataStormRegistry

    # @attr       = @Model.attr
    # @belongsTo  = @Model.belongsTo
    # @hasMany    = @Model.hasMany
    # @computed   = @Model.computed
    # @computedHistory = @Model.computedHistory

    async = require 'async'

    # DataStorm default properties schema
    logfile:   @attr 'string', defaultValue: "/tmp/#{@name}-@{@id}.log"
    loglevel:  @attr 'string', defaultValue: 'info'
    datadir:   @attr 'string', defaultValue: '/tmp'
    isMutable: @attr 'boolean', defaultValue: true # Allows this DataStorm to be changed via API calls

    # DataStorm auto-computed properties
    models: @computed (->
        # auto-calculate available models in this DataStorm
        @_models

    )
    host: @computed (-> 'something')



    constructor: ->
        super

        # create an instance of each model for the DataStorm to use
        v.instance = new v.model for k, v of @_models

        @collections = {} # the name of collection mapping to entity
        @entities = {}    # the name of entity mapping to entity object
        @entities = @extend(@entities, opts.entities) if opts?.entities?

        @authorizer = opts?.authorizer

        @isReady = false
        @datadir = opts?.datadir ? '/tmp'

        # if @constructor.name != 'DataStore'

        console.log "initializing a new DataStore: #{@name}"
        @log.info method:'constructor', 'initializing a new DataStore: %s', @name
        for name,prop of @properties
            continue unless prop.model? and prop.mode is 2

            do (name,prop) =>
                prop.registry ?= new DataStoreRegistry name, log:@log,store:@,persist:prop.opts?.persist
                if entity.static?
                    entity.registry.once 'ready', =>
                        @log.info collection:collection, 'loading static records for %s', collection
                        count = 0
                        for entry in entity.static
                            entry.saved = true
                            if entity.persist is false or not entity.registry.get(entry.id)?
                                entity.registry.add entry.id, entry
                                count++
                        @log.info collection:collection, "autoloaded #{count}/#{entity.static.length} static records"

        # setup any authorizer reference to this store
        if @authorizer instanceof DataStore
            @references @authorizer.contains 'identities'
            @authorizer.references @contains 'sessions'

        @log.info method:'initialize', 'initialization complete for: %s', @name
        console.log "initialization complete for: #{@name}"
        @isReady = true
        # this is not guaranteed to fire when all the registries have been initialized
        process.nextTick => @emit 'ready'

    #-------------------------------
    # main usage functions

    # opens the store according to the provided requestor access constraints
    # this should be subclassed for view control based on requestor
    open: (requestor) -> new DataStoreView @, requestor

    # register callback for being called on specific event against a collection
    #
    when: (collection, event, callback) ->
        entity = @contains collection
        assert entity? and entity.registry? and event in ['added','updated','removed'] and callback?, "must specify valid collection with event and callback to be notified"
        _store = @
        entity.registry.once 'ready', -> @on event, (args...) -> process.nextTick -> callback.apply _store, args

    deleteRecord: (type, id, callback) ->
        match = @findRecord type, id
        return callback? null unless match?
        match.destroy callback

    updateRecord: (type, id, data, callback) ->
        record = @findRecord type, id
        return callback? null unless record?
        record.update data
        record.save callback

    findRecord: (type, id) ->
        return unless type? and id?
        assert @entities[type]?.registry instanceof DataStoreRegistry, "trying to findRecord for #{type} without registry!"
        @entities[type]?.registry?.get id

    # findBy returns the matching records directly (similar to findRecord)
    findBy: (type, condition, callback) ->
        assert type? and typeof condition is 'object',
            "DS: invalid findBy query params!"

        @log.info method:'findBy',type:type,condition:condition, 'issuing findBy on requested entity'

        records = @entities[type]?.registry?.list() or []

        query = condition
        hit = Object.keys(query).length
        results = records.filter (record) =>
            match = 0
            for key,val of query
                try
                    x = record.get(key)
                    x = switch
                        when x instanceof DataStoreModel then x.id
                        when typeof x is 'boolean' and typeof val is 'string' then (if x then 'true' else 'false')
                        else x
                catch err
                    @log.debug method:'findBy',type:type,id:record.id,error:err,'skipping bad record...'
                    return false
                match += 1 if x is val or (x instanceof DataStoreModel and x.id is val)
            if match is hit then true else false

        unless results?.length > 0
            @log.info method:'findBy',type:type,condition:query,'unable to find any records for the condition!'
        else
            @log.info method:'findBy',type:type,condition:query,'found %d matching results',results.length
        callback? null, results
        results

    find: (type, query, callback) ->
        assert @entities.hasOwnProperty(type),
            "DS: unable to find using unsupported type: #{type}"

        _entity = @entities[type]
        ids = switch
            when query instanceof Array then query
            when query instanceof Object
                results = @findBy type, query
                results.map (record) -> record.id
            when query? then [ query ]
            else _entity.registry?.keys()

        self = @
        tasks = {}
        for id in ids
            do (id) ->
                tasks[id] = (callback) ->
                    match = self.findRecord type, id
                    return callback null unless match? and match instanceof DataStoreModel
                    # trigger a fresh computation and validations on the match
                    try
                        match.getProperties (err, props) -> callback null, match
                    catch err
                        self.log.warn error:err,type:type,id:id, 'unable to obtain validated properties from the matching record'
                        # below silently ignores this record
                        return callback null

        @log.debug method:'find',type:type,query:query, 'issuing find on requested entity'
        async.parallel tasks, (err, results) =>
            if err?
                @log.error err, "error was encountered while performing find operation on #{type} with #{query}!"
                return callback err

            matches = (entry for key, entry of results when entry?)
            unless matches?.length > 0
                @log.debug method:'find',type:type,query:query,'unable to find any records matching the query!'
            else
                @log.debug method:'find',type:type,query:query,'found %d matching results',matches.length

            callback null, matches

    commit: (record) ->
        return unless record instanceof DataStoreModel

        @log.debug method:"commit", record: record?.id

        registry = @entities[record.name]?.registry
        assert registry?, "cannot commit '#{record.name}' into store which doesn't contain the collection"

        action = switch
            when record.isDestroy
                registry.remove record.id
                'removed'
            when not record.isSaved
                exists = record.id? and registry.get(record.id)?
                assert not exists, "cannot commit a new record '#{record.name}' into the store using pre-existing ID: #{record.id}"
                registry.add record.id, record
                'added'
            when record.isDirty()
                record.changed = true
                registry.update record.id, record
                delete record.changed
                'updated'

        if action?
            # may be high traffic events, should listen only sparingly
            @emit 'commit', [ action, record.name, record.id ]
            @log.info method:"commit", id:record.id, "#{action} '%s' on the store registry", record.constructor.name

    #------------------------------------
    # useful for some debugging cases...
    dump: ->
        for name,entity of @entities
            records = entity.registry?.list()
            for record in records
                @log.info model:name,record:record.serialize(),method:'dump', "DUMP"

#---------------------------------------------------------------------------------------------------------

module.exports = DataStorm

### DEPRECATED

    # used to denote 'collection' that is stored inside this data store
    contains: (collection, entity) ->
        return @collections[collection] unless entity?

        entity.name = entity.model.prototype.name
        entity.container = @
        entity.persist ?= true # default is to persist data
        entity.cache   ?= 1 # default cache for 1 second
        entity.controller ?= DataStoreController
        entity.collection = collection

        @collections[collection] = @entities[entity.name] = entity
        @log.info collection:collection, "registered a collection of '#{collection}' into the store"

    # used to denote entity that is stored outside this data store
    references: (entity) ->
        assert entity.name? and entity.container instanceof DataStore, "cannot reference an entity that isn't contained by another store!"

        entity = extend {}, entity # get a copy of it
        entity.external = true # denote that this entity is an external reference!
        entity.persist = false
        entity.cache   = false
        @entities[entity.name] = entity
        @log.info reference:entity.name, "registered a reference to '#{entity.name}' into the store"

###
