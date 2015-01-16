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

class DataStoreModel extends SR.Data

    @attr      = (type, opts)  -> type: type, opts: opts
    @belongsTo = (model, opts) -> mode: 1, model: model, opts: opts
    @hasMany   = (model, opts) -> mode: 2, model: model, opts: opts
    @computed  = (func, opts)  -> computed: func, opts: opts
    @computedHistory = (model, opts) -> mode: 3, model: model, opts: opts

    @schema =
        id:         @attr 'any', defaultValue: -> (require 'node-uuid').v4()
        createdOn:  @attr 'date'
        modifiedOn: @attr 'date'
        accessedOn: @attr 'date'
        error:      @attr 'object'

    async = require 'async'
    extend = require('util')._extend

    schema: {}  # defined by sub-class
    store: null # auto-set by DataStore during createRecord

    constructor: (data,opts) ->
        @isSaving = @isSaved = @isDestroy = @isDestroyed = false

        @store = opts?.store
        @log = opts?.log?.child class: @constructor.name
        @log ?= new bunyan name: @constructor.name

        @useCache = opts?.useCache

        # initialize all relations and properties according to schema
        @relations = {}
        @properties = {}

        @schema = extend @schema, DataStoreModel.schema

        for key,val of @schema
            @properties[key] = extend {},val
            @relations[key] = {
                type: switch val.mode
                    when 1 then 'belongsTo'
                    when 2 then 'hasMany'
                model: val.model
            } if val.model?

        assert Object.keys(@properties).length > 0, "cannot construct a new data model without declared schema properties!"

        @revision ?= 1

        return @ unless data?

        @setProperties data
        @id = @get('id')

        # verify basic schema compliance during construction
        violations = []
        for name,prop of @properties
            #console.log name
            prop.value ?= switch
                when typeof prop.opts?.defaultValue is 'function' then prop.opts.defaultValue.call @
                else prop.opts?.defaultValue
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

    typeOf:     (property) -> @properties[property]?.type
    instanceOf: (property) -> @properties[property]?.model

    # customize how data gets saved into DataStoreRegistry
    # this operation cannot be async, it means it will extract only known current values.
    # but it doesn't matter since computed data will be re-computed once instantiated
    serialize: (opts) ->
        assert @isDestroyed is false, "attempting to serialize a destroyed record"

        result = id: @id
        for prop,data of @properties when data.value?
            x = data.value
            result[prop] = switch
                when x instanceof DataStoreModel
                    if opts?.embedded is true
                        x.serialize()
                    else
                        x.id
                when x instanceof Array
                    (if y instanceof DataStoreModel then y.id else y) for y in x
                else x

        return result unless opts?.tag is true

        data = {}
        data["#{@name}"] = result
        data

    get: (property, opts..., callback) ->
        assert @properties.hasOwnProperty(property), "attempting to retrieve '#{property}' which doesn't exist in this model"
        #assert @isDestroyed is false, "attempting to retrieve '#{property}' from a destroyed record"

        prop = @properties[property]

        enforceCheck = if opts.length then opts[0].enforce else true

        # simple property options enforcement routine
        #
        # unique: true (for array types, ensures only unique entries)
        enforce = (x) ->
            return x unless enforceCheck

            @log.debug "checking #{property} with '#{x}' as #{prop.model}"
            x ?= switch
                when typeof prop.opts?.defaultValue is 'function' then prop.opts.defaultValue.call @
                else prop.opts?.defaultValue

            violations = []
            validator = prop?.opts?.validator
            val = switch
                when not x?
                    @log.debug "value is empty"
                    violations.push "'#{property}' is a required property for #{@name}" if prop.opts?.required
                    if prop.mode is 2 then [] else null
                when prop.model? and typeof prop.model isnt 'string'
                    unless x instanceof prop.model
                        violations.push "'#{property}' must be an instance of #{prop.model.prototype?.constructor?.name}"
                    switch prop.mode
                        when 1 then x
                        when 2 then [ x ]
                when prop.model? and prop.mode is 2 and x instanceof Array
                    @log.debug "resolving hasMany"
                    unless x.length > 0 then x
                    else
                        x.map( (e) =>
                            switch
                                when e instanceof DataStoreModel then e
                                else @store.findRecord(prop.model,e)
                        ).filter( (e) -> e? ).unique()
                when prop.model? and x instanceof DataStoreModel
                    @log.debug "resolving belongsTo"
                    switch prop.mode
                        when 1 then x
                        when 2 then [ x ]
                when prop.model? and typeof x is 'object'
                    @log.debug "should be model but just returning object #{x}"
                    x
                when prop.model? and prop.mode isnt 3
                    @log.debug "attempting to resolve record with #{x}"
                    record = @store.findRecord(prop.model,x)
                    unless record?
                        violations.push "'#{property}' must be a model of #{prop.model}, unable to find using #{x}"
                    switch prop.mode
                        when 1 then record
                        when 2
                            if record? then [ record ] else []
                        when 3 then null # null for now
                when x instanceof Array and prop.opts?.unique is true
                    @log.debug "converting array to unique and defined values"
                    x.filter( (e) -> e? ).unique()
                else
                    @log.debug "nothing matched..."
                    x

            assert violations.length is 0, violations
            if validator? then validator.call(@, val) else val

        # should provide resolved results
        if typeof prop?.computed is 'function' and @store.isReady
            @log.debug "issuing get on computed property: %s", property
            value = prop.value = enforce.call @, prop.value
            if value and @useCache and prop.cachedOn and (prop.opts?.cache isnt false)
                cachedFor = (new Date() - prop.cachedOn)/1000
                if cachedFor < @useCache
                    @log.debug method:'get',property:property,id:@id,"returning cached value... will refresh in #{@useCache - cachedFor} seconds"
                    callback? null, value
                    return value
                else
                    @log.info method:'get',property:property,id:@id, "re-computing expired cached property (#{cachedFor} secs > #{@useCache} secs)"

            @log.debug method:'get',property:property,id:@id,"computing a new value!"

            try
                if prop.opts?.async
                    prop.computed.call @, (err, value) =>
                        return callback? err, value if err?
                        value = prop.value = enforce.call @, value
                        prop.cachedOn = new Date() if @useCache
                        callback? null, value
                else
                    x = prop.computed.apply @
                    value = prop.value = enforce.call @, x
                    callback? null, value
            catch err
                @log.debug method:'get',property:property,id:@id,error:err, "issue during executing computed property"
                callback? err
                return value

            value # this is to avoid returning a function when direct 'get' is invoked
        else
            @log.debug "issuing get on static property: %s", property
            prop.value = enforce.call(@, prop?.value) if @store.isReady
            value = prop.value
            @log.debug method:'get',property:property,id:@id,"issuing get on #{property}"
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
                    self.log.debug "scheduling task for computed property: #{property}..."
                    tasks[property] = (callback) -> self.get property, callback
                    self.log.debug "completed task for computed property: #{property}..."

        start = new Date()
        async.parallel tasks, (err, results) =>
            return callback err if err?

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
                "processing properties took #{duration} ms exceeding threshold!") if duration > 1000

            @log.debug method:'getProperties',id:@id,results:Object.keys(results), 'final results before callback'
            callback null, results

    set: (property, opts..., value) ->
        assert @isDestroyed is false, "attempting to set a value to a destroyed record"

        return @ if @schema? and not @properties.hasOwnProperty(property)

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
                if @properties[property].opts?.required
                    assert value?, "must set value for required property '#{property}'"

                @properties[property] = extend @properties[property], setting
            else
                @properties[property] = setting

        # now apply opts into the property if applicable
        #@properties[property].opts = opts if opts?

        @ # make it chainable

    setProperties: (obj) ->
        return unless obj instanceof Object
        @set property, value for property, value of obj

    update: (data) ->
        assert @isDestroyed is false, "attempting to update a destroyed record"

        # if controller associated, issue the updateRecord action call
        @controller?.beforeUpdate? data
        @setProperties data
        @controller?.afterUpdate? data

    # deal with DIRT properties
    dirtyProperties: -> (prop for prop, data of @properties when data.isDirty)
    clearDirty: -> data.isDirty = false for prop, data of @properties
    isDirty: (properties) ->
        dirty = @dirtyProperties()
        return (dirty.length > 0) unless properties?
        properties = [ properties ] unless properties instanceof Array
        dirty = dirty.join ' '
        properties.some (prop) -> ~dirty.indexOf prop

    removeReferences: (model,isSaveAfter) ->
        return unless model instanceof DataStoreModel
        changes = 0
        for key, relation of @relations
            continue unless relation.model is model.name
            @log.debug method:'removeReferences',id:@id,"clearing #{key}.#{relation.type} '#{relation.model}' containing #{model.id}..."
            try
                switch relation.type
                    when 'belongsTo' then @set key, null if @get(key)?.id is model.id
                    when 'hasMany'   then @set key, @get(key).without id:model.id
            catch err
                @log.debug method:'removeReferences', error:err, "issue encountered while attempting to clear #{@name}.#{key} where #{relation.model}=#{model.id}"

        @save() if @isSaved is true and isSaveAfter is true and @isDirty()

    save: (callback) ->
        assert @isDestroyed is false, "attempting to save a destroyed record"

        if @isSaving is true
            return callback? null, @

        @isSaving = true
        try
            @controller?.beforeSave?()
        catch err
            @log.error method:'save',record:@name,id:@id,error:err,'failed to satisfy beforeSave controller hook'
            @isSaving = false
            callback? err
            throw err

        # getting properties performs validations on this model
        @getProperties (err,props) =>
            if err?
                @log.error method:'save',id:@id,error:err, 'failed to retrieve validated properties before committing to store'
                return callback err

            @log.debug method:'save',record:@name,id:@id, "saving record"
            try
                @store?.commit @
                @clearDirty()
            catch err
                @log.warn method:'save',record:@name,id:@id,error:err,'issue during commit record to the store, ignoring...'

            try
                @controller?.afterSave?()
                @isSaved = true

                callback? null, @, props
            catch err
                @log.error method:'save',record:@name,id:@id,error:err,'failed to commit record to the store!'

                # we self-destruct only if this record wasn't saved previously
                @destroy() unless @isSaved is true

                callback? err
                throw err

            finally
                @isSaving = false

    # a method to invoke an action on the controller for the record
    invoke: (action, params, data) ->
        new (require 'promise') (resolve,reject) =>
            try
                resolve @controller?.actions[action]?.call(@controller, params, data)
            catch err
                reject err

    destroy: (callback) ->
        # if controller associated, issue the destroy action call
        @isDestroy = true
        try
            @controller?.beforeDestroy?()
            @store?.commit @
            @isDestroyed = true
            @controller?.afterDestroy?()
        catch err
            @log.warn method:'destroy',record:@name,id:@id,error:err,'encountered issues during destroy, ignoring...'
        finally
            callback? null, true

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

class DataStore extends DataStoreModel

    # various extensions available from this class object
    @Model      = DataStoreModel
    @Controller = DataStoreController
    @View       = DataStoreView
    @Registry   = DataStoreRegistry

    # @attr       = @Model.attr
    # @belongsTo  = @Model.belongsTo
    # @hasMany    = @Model.hasMany
    # @computed   = @Model.computed
    # @computedHistory = @Model.computedHistory

    async = require 'async'
    uuid  = require 'node-uuid'
    extend = require('util')._extend

    name: 'ds'
    schema: null

    adapters: {}
    adapter: (type, module) -> @adapters[type] = module if type? and module?
    using: (adapter) -> @adapters[adapter]

    constructor: (data,opts) ->
        super data, opts

        @collections = {} # the name of collection mapping to entity
        @entities = {}    # the name of entity mapping to entity object
        @entities = extend(@entities, opts.entities) if opts?.entities?

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

    createRecord: (type, data) ->
        @log.debug method:"createRecord", type: type
        try
            entity = @entities[type]
            record = new entity.model data,store:entity.container,log:@log,useCache:entity.cache

            # XXX - should consider this ONLY when created from a view
            record.controller = new entity.controller
                model:record
                view: this
                log: @log

            @log.debug  method:"createRecord", id: record.id, 'created a new record for %s', record.constructor.name
        catch err
            @log.error error:err, "unable to instantiate a new DS.Model for #{type}"
            throw err
        record

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

                # if there is no ID specified for this entity, we auto-assign one at the time we commit
                record.id ?= uuid.v4()
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

module.exports = DataStore
