StormModel   = require './storm/storm-model'
StormObject  = require './storm/storm-object'

class DataStorm extends StormModel
  @set storm: 'datastorm', name: 'stormify-data', models: new ModelRegistry

  # various extensions available from this class object
  @Model  = StormModel
  @Object = StormObject

  # Storm default properties schema
  #logfile:   @attr 'string', defaultValue: @computed -> "/tmp/#{@constructor.name}-#{@get('id')}.log"
  loglevel:  @attr 'string', defaultValue: 'info'
  datadir:   @attr 'string', defaultValue: '/tmp'

  # Allows this DataStorm to be changed via API calls (future)
  #isMutable: @attr 'boolean', defaultValue: true

  # DataStorm can have collection of other storms
  storms: @hasMany DataStorm, private: true

  # DataStorm auto-computed properties
  models: @computed (-> (@constructor.get 'models').serialize() )

  ###*
  # `addProperty` for DataStorm checks for new hasMany relationships
  # being added and registers the model to the private _models
  # registry and OVERRIDES the property to the corresponding
  # ModelRegistryProperty
  ###
  addProperty: (key, prop) ->
    if prop instanceof StormModel.Property and prop.kind is 'hasMany' and prop.opts.private isnt true
      prop = @_models.register prop.model, prop.opts
    super key, prop

  ###*
  # PUBLIC access methods for working directly with PRIVATE _models registry
  ###
  create: (type, data) -> null
  find:   (type, query) -> @_models.find type, query
  update: (type, id, data) -> null
  delete: (type, query) -> model.destroy() for model in (@find type, query)

  contains: (key) ->
    prop = @getProperty key
    prop if prop instanceof StormModel.Registry.Property

  infuse: (opts) ->
    console.log "using: #{opts?.source}"

  #-------------------------------
  # main usage functions

  # opens the store according to the provided requestor access constraints
  # this should be subclassed for view control based on requestor
  open: (requestor) -> new StormView @, requestor

  # register callback for being called on specific event against a collection
  #
  when: (collection, event, callback) ->
      entity = @contains collection
      assert entity? and entity.registry? and event in ['added','updated','removed'] and callback?, "must specify valid collection with event and callback to be notified"
      _store = @
      entity.registry.once 'ready', -> @on event, (args...) -> process.nextTick -> callback.apply _store, args

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

