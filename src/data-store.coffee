# mixin = require './mixin'
# DynamicResolver    = require './dynamic-resolver'
# extends mixin DynamicResolver
#
assert = require 'assert'
bunyan = require 'bunyan'

#---------------------------------------------------------------------------------------------------------

SR = require 'stormregistry'

class DataStoreRegistry extends SR

    constructor: (@entity,opts) ->
        assert entity instanceof Object and entity.model?, "cannot construct DataStoreRegistry without valid entity passed in"

        @store = opts?.store
        @log = opts?.log?.child class: @constructor.name
        @log ?= new bunyan name: @constructor.name

        @on 'load', (key,val) ->
            @log.debug entity:@entity.name,key:key,'loading a persisted record'
            entry = val?[@entity.name]
            if entry?
                entry.id = key
                entry.saved = true
                @add key, entry
        @on 'ready', ->
            @log.info entity:@entity.name,size:Object.keys(@entries)?.length,'registry is initialized and ready'

        datadir = opts?.datadir ? '/tmp'
        super
            log: @log
            path: "#{datadir}/#{entity.name}.db" if entity.persist

    get: (id) ->
        entry = super id
        return null unless entry?
        unless entry instanceof DataStoreModel
            @update id, new @entity.model(entry, store:@store,log:@log)
        super id

#---------------------------------------------------------------------------------------------------------

class DataStoreModel extends SR.Data

    async = require 'async'
    extend = require('util')._extend
    uuid  = require 'node-uuid'

    schema: null # defined by sub-class
    store: null  # auto-set by DataStore during createRecord

    constructor: (data,opts) ->
        @properties =
            createdOn:  value: null
            modifiedOn: value: null
            accessedOn: value: null

        @isSaved = false

        @store = opts?.store

        @log = opts?.log?.child class: @constructor.name
        @log ?= new bunyan name: @constructor.name

        @log.debug data:data, "constructing #{@name}"

        # initialize all properties according to schema
        for key,val of @schema when @schema?
            do (val) =>
                @properties[key] = extend {},val

        @id = data?.id
        @id ?= uuid.v4()
        @version ?= 1
        @setProperties data

        # verify basic schema compliance during construction
        violations = []
        for name,prop of @properties
            #console.log name
            prop.value ?= prop.opts?.defaultValue
            unless prop.value
                violations.push "'#{name}' is required for #{@constructor.name}" if prop.opts?.required
            else
                check = switch prop.type
                    when 'string' or 'number' or 'boolean'
                        typeof prop.value is prop.type
                    when 'date'
                        if typeof prop.value is 'string'
                            prop.value = new Date(prop.value)
                        prop.value instanceof Date
                    when 'array'
                        prop.value instanceof Array
                    else
                        true

                violations.push "'#{name}' must be a #{prop.type}" if prop.type? and not check

                if prop.model? and prop.value instanceof Array and prop.mode isnt 2
                    violations.push "'#{name}' cannot be an array of #{prop.model}"
            prop.value ?= [] if prop.mode is 2

        @log.debug "done constructing #{@name}"
        assert violations.length == 0, violations

    # customize how data gets saved into DataStoreRegistry
    # this operation cannot be async, it means it will extract only known current values.
    # but it doesn't matter since computed data will be re-computed once instantiated
    serialize: (notag) ->
        result = id: @id
        for prop,data of @properties when data.value?
            x = data.value
            result[prop] = switch
                when x instanceof DataStoreModel then x.id
                when x instanceof Array
                    (if y instanceof DataStoreModel then y.id else y) for y in x
                else x

        return result if notag

        data = {}
        data["#{@name}"] = result
        data

    get: (property, callback) ->
        assert @properties.hasOwnProperty(property), "attempting to retrieve '#{property}' which doesn't exist in this model"

        prop = @properties[property]

        # simple property options enforcement routine
        #
        # unique: true (for array types, ensures only unique entries)
        enforce = (x) ->
            #console.log "checking #{property} with #{x}"
            #
            violations = []
            validator = prop?.opts?.validator
            val = switch
                when not x
                    violations.push "'#{property}' is a required property" if prop.opts?.required
                    null
                when prop.model? and x instanceof Array and prop.mode is 2
                    results = (@store.findRecord(prop.model,id) for id in prop.value unless id instanceof DataStoreModel).filter (e) -> e?
                    if results.length then results else x
                when prop.model? and x instanceof DataStoreModel
                    switch prop.mode
                        when 1 then x
                        when 2 then [ x ]
                when prop.model? and x instanceof Object
                    try
                        inverse = prop.opts?.inverse
                        x[inverse] = @ if inverse?
                        record = @store.createRecord prop.model,x
                    catch err
                        @log.warn error:err, "attempt to auto-create #{prop.model} failed"
                        record = x
                    #XXX - why does record.save() hang?
                    #record.save()
                    record
                when prop.model? and prop.mode isnt 3
                    #console.log "#{prop.model} using #{x}"
                    record = @store.findRecord(prop.model,x)
                    unless record?
                        violations.push "'#{property}' must be a model of #{prop.model}, unable to find using #{x}"
                    switch prop.mode
                        when 1 then record
                        when 2 then [ record ]
                        when 3 then null # null for now
                when x instanceof Array and prop.opts.unique then x.unique()
                else x
            assert violations.length is 0, violations
            if validator? then validator.call(@, val) else val

        # should provide resolved results
        if typeof prop?.computed is 'function' and @store.isReady
            @log.debug "issuing get on computed property: %s", property
            value = prop.value = enforce.call @, prop.value
            if value and @useCache and prop.cachedOn and (prop.opts?.cache isnt false)
                cachedFor = (new Date() - prop.cachedOn)/1000
                if cachedFor < @useCache
                    @log.info method:'get',property:property,id:@id,"returning cached value: #{value} will refresh in #{@useCache - cachedFor} seconds"
                    callback? null, value
                    return value
                else
                    @log.info method:'get',property:property,id:@id, "re-computing expired cached property (#{cachedFor} secs > #{@useCache} secs)"

            @log.debug method:'get',property:property,id:@id,"computing a new value!"
            cacheComputed = (err, value) =>
                unless err and @useCache
                    prop.value = value
                    prop.cachedOn = new Date()
                callback? err, enforce.call(@,value)

            if prop.opts?.async
                prop.computed.apply @, [cacheComputed,prop]
            else
                prop.value = prop.computed.apply @
                callback? null, enforce.call @, prop.value

            value # this is to avoid returning a function when direct 'get' is invoked
        else
            @log.info "issuing get on static property: %s", property
            prop.value = enforce.call(@, prop?.value) if @store.isReady
            value = prop.value
            @log.debug method:'get',property:property,id:@id,"issuing get on #{property} with #{value}"
            callback? null, value
            value

    getProperties: (props, callback) ->
        if typeof props is 'function'
            callback = props
            props = @properties
        else
            props = [ props ] if props? and props not instanceof Array
            props ?= @properties

        self = @
        tasks = {}
        for property, value of props
            if typeof value.computed is 'function'
                do (property) ->
                    self.log.info "scheduling task for computed property: #{property}..."
                    tasks[property] = (callback) -> self.get property, callback

        start = new Date()
        async.parallel tasks, (err, results) =>
            results.id = @id
            @log.trace method:'getProperties',id:@id,results:results, 'computed properties'
            statics = {}
            statics[property] = @get property for property, data of props when not data.computed
            @log.trace method:'getProperties',id:@id,statics:statics, 'static properties'
            results = extend statics, results
            delete results[property] for property of results when property.indexOf('++') > 0

            duration = new Date() - start
            (@log.warn
                method:'getProperties'
                duration:duration
                numComputed: Object.keys(tasks).length
                id: @id
                computed: Object.keys(tasks)
                results: results
                "processing properties took #{duration} ms exceeding threshold!") if duration > 1000

            @log.debug method:'getProperties',id:@id,results:results, 'final results before callback'
            callback results

    set: (property, opts..., value) ->
        return if @schema? and not @properties.hasOwnProperty(property)

        if typeof value is 'function'
            if property instanceof Array
                @properties[prop] = inherit: true for prop in property
                property = property.join '++'
            @properties[property]?.computed = value
            @properties[property] ?= computed: value
        else
            ArrayEquals = (a,b) -> a.length is b.length and a.every (elem, i) -> elem is b[i]
            cval = @properties[property]?.value
            nval = value
            isDirty = switch
                when not @properties.hasOwnProperty(property) then false # when being set for the first time
                when cval is nval then false
                when cval instanceof Array and nval instanceof Array then not ArrayEquals cval,nval
                else true
            @log.debug method:'set',property:property,id:@id,"compared #{property} #{cval} with #{nval}... isDirty:#{isDirty}"
            setting = isDirty:isDirty,lvalue:cval,value:nval
            if @properties.hasOwnProperty(property)
                @properties[property] = extend @properties[property], setting
            else
                @properties[property] = setting
        # now apply opts into the property if applicable
        #@properties[property].opts = opts if opts?

    setProperties: (obj) -> @set property, value for property, value of obj

    update: (data) ->
        @setProperties data
        # if controller associated, issue the updateRecord action call
        @controller?.update data if @store.isReady

    # deal with DIRT properties
    dirtyProperties: -> (prop for prop, data of @properties when data.isDirty)
    clearDirty: -> data.isDirty = false for prop, data of @dirtyProperties()
    isDirty: (properties) ->
        dirty = @dirtyProperties()
        return (dirty.length > 0) unless properties?
        properties = [ properties ] unless properties instanceof Array
        dirty = dirty.join ' '
        properties.some (prop) -> ~dirty.indexOf prop

    save: (callback) ->
        state = switch
            when not @isSaved then 'new'
            when @isDirty() then 'changed'
            else 'unchanged'
        @log.info method:'save',id:@id, "saving a %s record", state
        if @isDirty() or not @isSaved
            @getProperties (props) =>
                unless props?
                    @log.error method:'save',id:@id,'failed to retrieve properties following save!'
                    callback? 'save failed to retrieve updated properties!', null
                else
                    @store?.commit @
                    @clearDirty()
                    @isSaved = true
                    callback? null, @

    destroy: (callback) ->
        # if controller associated, issue the destroy action call
        @controller?.destroy data if @store.isReady

        @store?.commit @, true
        callback null, true

#---------------------------------------------------------------------------------------------------------

EventEmitter = require('events').EventEmitter

class DataStoreController extends EventEmitter

    constructor: (@model,opts) ->
        assert model instanceof DataStoreModel, "unable to create an instance of DS.Controller without underlying model!"

        model.controller ?= this

        @store = model.store
        @create opts?.data if @store.isReady

    create: (data) ->
        @model.set 'createdOn', new Date()
        @model.set 'modifiedOn', new Date()
        @model.set 'accessedOn', new Date()

        @emit 'createRecord', [ @model.name, @model.id ]

    update: (data) ->
        @model.set 'modifiedOn', new Date()

        @emit 'updateRecord', [ @model,name, @model.id ]

    destroy: (data) ->

        @emit 'destroyRecord', [ @model.name, @model.id ]

#---------------------------------------------------------------------------------------------------------

class DataStore

    async = require 'async'
    uuid  = require 'node-uuid'
    extend = require('util')._extend

    adapters: {}
    adapter: (type, module) -> @adapters[type] = module
    using: (adapter) -> @adapters[adapter]

    constructor: (opts) ->
        @log = opts?.auditor?.child class: @constructor.name
        @log ?= new bunyan name: @constructor.name

        @authorizer = opts?.authorizer

        @entities = {}
        @entities = extend(@entities, opts.entities) if opts?.entities?

        @isReady = false

        # if @constructor.name != 'DataStore'
        #   assert Object.keys(@entities).length > 0, "cannot have a data store without declared entities!"

    initialize: ->
        return if @isReady
        for collection, entity of @entities
            entity.registry = new DataStoreRegistry entity,log:@log,store:@
            if entity.static?
                created = 0
                for entry in entity.static
                    do (entry) =>
                        record = @createRecord(entity.name, entry)
                        assert record?, "#{entry} failed to be created!"
                        record?.save()
                        created++ if record?
                assert created is entity.static.length, "failed to create all the static records!"
                @log.info collection:collection, "autoloaded #{entity.static.length} static records"
        @isReady = true

    contains: (collection, entity) ->
        entity.collection = collection
        entity.name = entity.model.prototype.name
        entity.persist ?= true # default is to persist data
        entity.cache   ?= 1 # default cache for 1 second
        entity.controller ?= DataStoreController
        @entities[entity.name] = entity

        @log.info collection:collection, "registered a collection of '#{collection}' into the store"

    dump: ->
        for name,entity of @entities
            records = entity.registry?.list()
            for record in records
                @log.info model:name,record:record.serialize(),method:'dump', "DUMP"

    createRecord: (type, data) ->
        match = @findRecord type, data?.id
        return if match?

        #@log.info method:"createRecord", type: type, data: data
        try
            entity = @entities[type]
            record = new entity.model data,store:this,log:@log
            record.useCache = entity.cache
            record.controller = new entity.controller record,log:@log

            #record?.controller = @entities[type].controller
            @log.info  method:"createRecord", id: record.id, 'created a new record for %s', record.constructor.name
            #@log.debug method:"createRecord", record:record
        catch err
            @log.error err, "unable to instantiate a new DS.Model for #{type}"
            throw err
        record

    deleteRecord: (type, id, callback) ->
        match = @findRecord type, id
        callback null unless match?
        match.destroy callback

    updateRecord: (type, id, data, callback) ->
        @find type, id, (err, matches) =>
            if matches? and matches.length is 1
                record = @findRecord type, matches[0].id
                record.update data
                if record
                  record.save callback
                else
                   callback null
            else
                @log.warn method:'updateRecord',type:type,id:id,'unable to find existing record to update!'
                callback null

    findRecord: (type, id) ->
        return unless type? and id?
        record = @entities[type]?.registry?.get id
        record

    # findBy returns the matching records directly (similar to findRecord)
    # XXX - only supports a single key: value pair for now
    findBy: (type, condition, callback) ->
        return callback "invalid findBy query params!" unless type? and typeof condition is 'object'

        @log.debug method:'find',type:type,condition:condition, 'issuing findBy on requested entity'
        [ key, value ] = ([key, value] for key, value of condition)[0]
        records = @entities[type]?.registry?.list() or []
        results = records.filter (record) ->
            x = record.get(key)
            x is value or x.id is value

        unless results?.length > 0
            @log.warn method:'findBy',type:type,condition:condition,'unable to find any records for the condition!'
        else
            @log.debug method:'findBy',type:type,condition:condition,'found %d matching results',results.length
        callback null, results

    # find returns the properties
    find: (type, query, callback) ->
        _entity = @entities[type]
        return callback "DS: unable to find using unsupported type: #{type}" unless _entity?
        #return callback "DS: unable to find without specified match condition" unless query?
        return callback null, _entity.registry?.list() unless query?

        query = [ query ] unless query instanceof Array

        self = @
        tasks = {}
        for id in query
            do (id) ->
                tasks[id] = (callback) ->
                    match = self.findRecord type, id
                    if match? and match instanceof DataStoreModel
                        #match.getProperties (properties) -> callback null, properties
                        match.getProperties (properties) -> callback null, match
                    else
                        return callback null unless _entity.helpers?.get?
                        # # attempt to self get the requested info only valid for ID based query condition
                        # _entity.helpers?.get.apply self, [id, (result) ->
                        #     record = self.createRecord type, result if result?
                        #     if record?
                        #         # if we get a new record, we save it to our internal registry
                        #         record.save callback
                        #     else
                        #         match = self.findRecord type, id
                        #         if match?
                        #             match.getProperties (props) -> callback null, props
                        #         else
                        #             self.log.warn method:'find',id:id, "unable to find or fetch #{type} record!"
                        #             callback null
                        # ]

        @log.info method:'find',type:type,query:query, 'issuing find on requested entity'
        async.parallel tasks, (err, results) =>
            if err?
                @log.error err, "error was encountered while performing find operation on #{type} with #{query}!"
                return callback err

            matches = (entry for key, entry of results when entry?)
            unless matches?.length > 0
                @log.warn method:'find',type:type,query:query,'unable to find any records matching the query!'
            else
                @log.debug method:'find',type:type,query:query,'found %d matching results',matches.length

            callback null, matches

    commit: (obj, isDestroy) ->
        return unless obj instanceof DataStoreModel

        @log.debug method:"commit", record: obj

        registry = (entity.registry for type, entity of @entities when entity.model?.prototype.constructor.name is obj.constructor.name)[0]
        return unless registry

        isDestroy ?= false

        # controller = obj.controller
        # obj.controller = null

        # if there is no ID specified for this entity, we auto-assign one at the time we commit
        obj.id ?= uuid.v4()
        match = registry.get obj.id
        unless match?
            registry.add(obj.id, obj) if not isDestroy
        else
            unless isDestroy
                obj.changed = true
                registry.update obj.id, obj
                delete obj.changed
            else
                registry.remove obj.id

        # obj.controller = controller
        @log.info method:"commit", id:obj.id, "updated the store registry for %s", obj.constructor.name
        obj

module.exports = DataStore
module.exports.Model = DataStoreModel
module.exports.Controller = DataStoreController
module.exports.Registry = DataStoreRegistry

module.exports.attr = (type, opts) -> type: type, opts: opts
module.exports.belongsTo = (model, opts) -> mode: 1, model: model, opts: opts
module.exports.hasMany = (model, opts) -> mode: 2, model: model, opts: opts
module.exports.computed = (func, opts) -> computed: func, opts: opts
module.exports.computedHistory = (model, opts) -> mode: 3, model: model, opts: opts
