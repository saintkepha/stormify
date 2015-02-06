# mixin = require './mixin'
# DynamicResolver    = require './dynamic-resolver'
# extends mixin DynamicResolver
#
assert = require 'assert'
bunyan = require 'bunyan'

#---------------------------------------------------------------------------------------------------------

SR = require './stormregistry'

#-----------------------------------
# DataStormRegistry
#
# Uses deferred DataStoreModel instantiation to take place only on @get
#
class DataStormRegistry extends SR

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

#---------------------------------------------------------------------------------------------------------

# Wrapper around underlying DataStore
#
# Used during store.open(requestor) in order to provide access context
# for store operations. Also, DataStore sub-classes can override the
# store.open call to manipulate the views into the underlying entities
class DataStormView

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

class DataStorm extends DataStormModel

  # various extensions available from this class object
  @Model      = DataStormModel
  # @View       = DataStormView
  # @Registry   = DataStormRegistry

  # DataStorm default properties schema
  logfile:   @attr 'string', defaultValue: @computed -> "/tmp/#{@_name}-#{@get('id')}.log"
  loglevel:  @attr 'string', defaultValue: 'info'
  datadir:   @attr 'string', defaultValue: '/tmp'

  # Allows this DataStorm to be changed via API calls (future)
  #isMutable: @attr 'boolean', defaultValue: true

  # DataStorm auto-computed properties
  models: @computed (->
    # auto-calculate available models in this DataStorm
    for k, v of @_models
      name: k
      numRecords: Object.keys(v.records).length
  )

  constructor: ->
    super

    ###
    #@authorizer = opts?.authorizer

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

    @log.info method:'initialize', 'initialization complete for: %s', @name
    console.log "initialization complete for: #{@name}"
    @isReady = true
    # this is not guaranteed to fire when all the registries have been initialized
    process.nextTick => @emit 'ready'
    ###

  #-------------------------------
  # main usage functions

  # opens the store according to the provided requestor access constraints
  # this should be subclassed for view control based on requestor
  open: (requestor) -> new DataStormView @, requestor

  # register callback for being called on specific event against a collection
  #
  when: (collection, event, callback) ->
      entity = @contains collection
      assert entity? and entity.registry? and event in ['added','updated','removed'] and callback?, "must specify valid collection with event and callback to be notified"
      _store = @
      entity.registry.once 'ready', -> @on event, (args...) -> process.nextTick -> callback.apply _store, args

  findRecord:   (type, id) -> (@modelFor type)?.records[id]
  deleteRecord: (type, id) -> (@findRecord type, id)?.destroy()
  updateRecord: (type, id, data) -> ((@findRecord type, id)?.setProperties data)?.save()

  find: (type, query) ->
    records = (@modelFor type)?.records
    return null unless records?

    switch
      when query instanceof Array
        (v for k, v of records when k in query)
      when query instanceof Object
        (v for k, v of records).filter (e) -> e.match query
      when query?
        records[query]
      else
        (v for k, v of records)

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


module.exports = DataStorm

