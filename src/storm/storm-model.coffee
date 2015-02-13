StormObject = require './storm-object'

assert = require 'assert'

class RelationshipProperty extends StormObject.Property
  @set storm: 'relation'

  kind: null

  constructor: (@model, opts={}, obj) ->
    assert typeof @model?.constructor is 'function',
        "cannot register a new relationship without proper model class"
    assert obj instanceof StormModel,
        "cannot register a new relationship without containing obj defined"

    type = switch @kind
        when 'belongsTo' then 'string'
        when 'hasMany' then 'array'

    opts.unique = true if @kind is 'hasMany'
    super type, opts, obj

  #serialize: -> super @get()

class BelongsToProperty extends RelationshipProperty
  @set storm: 'belongsTo'

  kind: 'belongsTo'

  get: -> @model::fetch super

  validate:  (value=@value) -> (super value) is true and (not value? or @model::fetch value instanceof @model)
  normalize: (value) ->
    # console.log 'belongsTo.normalize'
    # console.log value
    # console.log (value instanceof @model)
    switch
      when not value? then undefined
      when value instanceof @model then value.get 'id'
      when typeof value is 'string' then value
      when typeof value is 'number' then "#{value}"
      when value instanceof Array then undefined
      when value instanceof Object
        record = new @model value
        @obj.bind record
        @normalize record
      else undefined

  serialize: (format='json') ->
    if @opts.embedded is true
      @get().serialize format
    else
      super

class HasManyProperty extends RelationshipProperty
  @set storm: 'hasMany'

  kind: 'hasMany'

  get: -> (super.map (e) => @model::fetch e).filter (e) -> e?

  push: (value) ->
    list = @get()
    list.push value
    @set list

  validate: (value=@value) -> (super value) is true and value.every (e) => (@model::fetch e) instanceof @model

  normalize: (value) ->
    # console.log "normalizing hasMany for #{@model['meta-name']}"
    value = super value
    super switch
      when value instanceof Array
        (value.filter (e) -> e?).map (e) => BelongsToProperty::normalize.call this, e
      else undefined

  serialize: (format='json') ->
    # console.log 'serializing hasMany...'
    # console.log @value
    if @opts.embedded is true
      @get().map (e) -> e.serialize format
    else
      super

StormRegistry = require './storm-registry'

class ModelRegistryProperty extends StormRegistry.Property

  constructor: (@model, opts, obj) -> super 'object', opts, obj

  match: (query, keys=false) ->
    switch
      when query instanceof Array then super
      when query instanceof Object
        for k, v of @get() when v.match query
          if keys then k else v
      else
        super

  serialize: (format='json') ->
    ids: Object.keys(@value)
    numRecords: Object.keys(@value).length

class ModelRegistry extends StormRegistry

  @Property = ModelRegistryProperty

  register: (model, opts) ->
    # may not need this...
    # model.meta ?= name: model.name
    # model.meta.name ?= model.name
    super model.meta.name, new ModelRegistryProperty model, opts, this

  add: (records...) ->
    obj = {}
    obj[record.get('id')] = record for record in records when record instanceof StormModel
    super record.constructor.meta.name, obj

  remove: (records...) ->
    query = (record.get('id') for record in records when record instanceof StormModel)
    super record.constructor.meta.name, query

  contains: (key) -> (@getProperty key)

class StormModel extends StormObject
  @set storm: 'model'

  @belongsTo = (model, opts) ->
    class extends BelongsToProperty
      @set type: model, opts: opts

  @hasMany = (model, opts) ->
    class extends HasManyProperty
      @set type: model, opts: opts

  @action = (func, opts)  ->
    class extends ActionProperty
      @set type: func, opts: opts

  @RelationshipProperty = RelationshipProperty
  @HasManyProperty = HasManyProperty
  @BelongsToProperty = BelongsToProperty

  # default schema for all StormModels
  id:         @attr 'string', private: true, defaultValue: -> (require 'node-uuid').v4()
  createdOn:  @attr 'date', private: true, defaultValue: -> new Date
  modifiedOn: @attr 'date', private: true, defaultValue: -> new Date
  accessedOn: @attr 'date', private: true, defaultValue: -> new Date

  # internal tracking of bound model records
  _bindings: @hasMany StormModel, private: true

  # this is a PRIVATE shared prototype singleton ModelRegistry
  # instance visible across ALL model instances (intentionally
  # undocumented)
  #
  # It is publicly accessible via the DataStorm class
  _models: new ModelRegistry

  constructor: ->
    super
    @_models.register @constructor
    @_models.add this

  get: ->
      @set 'accessedOn', new Date
      super

  fetch: (id) -> @_models.find @constructor.meta.name, id

  getRelationships: (kind) ->
      @everyProperty (key) -> this if this instanceof RelationshipProperty
      .filter (x) -> x? and (not kind? or kind is x.kind)

  ###*
  # `bind` subjugates passed in records to be bound to the lifespan of
  # the current model record.
  #
  # When this current model record is destroyed, all bound dependents
  # will also be destroyed.
  ###
  bind: (records...) ->
    for record in records
      continue unless record? and record instanceof StormModel
      (@getProperty '_bindings').push record.save()

  match: (query) ->
      for k, v of query
          x = (@getProperty k)?.normalize (@get k)
          x = "#{x}" if typeof x is 'boolean' and typeof v is 'string'
          return false unless x is v
      return true

  save: ->
    # XXX - a bit ugly at the moment...
    # console.log 'SAVING:'
    isValid = @validate()
    # console.log isValid
    if isValid.length is 0
        (@set 'modifiedOn', new Date) if @isDirty()
        @clearDirty()
        @_models.add this
        this
    else
        null

  destroy: ->
      record.destroy() for record in @get '_bindings'
      @_models.remove this

  Promise = require 'promise'
  invoke: (action, args...) ->
    new Promise (resolve, reject) =>
      try
        unless action instanceof Function
          action = (@getProperty action)?.exec
        resolve (action?.apply this, args)
      catch err
        reject err

module.exports = StormModel
