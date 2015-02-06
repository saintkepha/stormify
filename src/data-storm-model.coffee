DataStormObject = require './data-storm-object'

assert = require 'assert'

class RelationshipProperty extends DataStormObject.Property

  kind: null

  constructor: (@model, opts={}, obj) ->
    assert typeof model?.constructor is 'function',
        "cannot register a new relationship without proper model class"
    assert obj instanceof DataStormModel,
        "cannot register a new relationship without containing obj defined"

    type = switch @kind
        when 'belongsTo' then 'string'
        when 'hasMany' then 'array'

    opts.unique = true if @kind is 'hasMany'
    super type, opts, obj

  serialize: -> super @get()

class BelongsToProperty extends RelationshipProperty

  kind: 'belongsTo'

  get: -> @model::fetch super

  validate:  (value=@value) -> (super value) is true and (not value? or @model::fetch value instanceof @model)
  normalize: (value) ->
    #console.log 'belongsTo.normalize'
    super switch
      when not value? then undefined
      when value instanceof @model then value.get('id')
      when typeof value is 'string' then value
      when typeof value is 'number' then "#{value}"
      when value instanceof Array then undefined
      when value instanceof Object
        record = new @model value
        @obj.bind record
        @normalize record
      else undefined
  serialize: ->
    if @opts.embedded is true
      @get().serialize()
    else
      super

class HasManyProperty extends RelationshipProperty

  kind: 'hasMany'

  get: -> (super.map (e) => @model::fetch e).filter (e) -> e?

  push: (value) ->
    list = @get()
    list.push value
    @set list

  validate: (value=@value) -> (super value) is true and value.every (e) => (@model::fetch e) instanceof @model

  normalize: (value) ->
    #console.log 'normalizing hasMany'
    super switch
      when value instanceof Array
        (value.filter (e) -> e?).map (e) =>
          BelongsToProperty::normalize.call this, e
      else undefined

  serialize: ->
    #console.log 'serializing hasMany'
    if @opts.embedded is true
      @get().map (e) -> e.serialize()
    else
      super

class DataStormModel extends DataStormObject

  @belongsTo = (model, opts) -> stormify: -> new BelongsToProperty model, opts, this
  @hasMany   = (model, opts) -> stormify: -> new HasManyProperty model, opts, this
  @action    = (func, opts)  -> stormify: -> new ActionProperty func, opts, this

  # default schema for all DataStormModels
  id:         @attr 'string', defaultValue: -> (require 'node-uuid').v4()
  createdOn:  @attr 'date', defaultValue: -> new Date
  modifiedOn: @attr 'date', defaultValue: -> new Date
  accessedOn: @attr 'date', defaultValue: -> new Date

  # internal tracking of bound model records
  _bindings: @hasMany DataStormModel

  # this is a PRIVATE shared prototype hash map visible across ALL
  # model instances (intentionally undocumented)
  _models: {}

  constructor: (data) ->
    super data
    @_id = @get('id')
    @_name = @constructor.name

    unless @_models.hasOwnProperty @constructor.name
        @_models[@constructor.name] =
            model: @constructor
            records: {}

  get: ->
      @set 'accessedOn', new Date
      super

  fetch: (id) -> @_models[@constructor.name]?.records?[id]
  modelFor: (modelName) -> @_models[modelName]

  getRelationships: (kind) ->
      @everyProperty (key) -> this if this instanceof RelationshipProperty
      .filter (x) -> x? and (not kind? or kind is x.kind)

  bind: (records...) ->
    for record in records
      continue unless record? and record instanceof DataStormModel
      (@getPropertyObject '_bindings').push record.save()

  match: (query) ->
      for k, v of query
          x = (@getPropertyObject k)?.normalize (@get k)
          x = "#{x}" if typeof x is 'boolean' and typeof v is 'string'
          return false unless x is v
      return true

  save: ->
    #console.log 'SAVING:'
    isValid = @validate()
    #console.log isValid
    if isValid.length is 0
        (@set 'modifiedOn', new Date) if @isDirty()
        @clearDirty()
        @_models[@constructor.name].records[@_id] = this
        this
    else
        null

  destroy: ->
      record.destroy() for record in @get '_bindings'
      delete @_models[@constructor.name].records[@_id]

  @Promise = require 'promise'
  # a method to invoke a registered promised action on the record
  invoke: (action, params, data) ->
      new @Promise (resolve,reject) =>
          try
              resolve @_actions[action]?.call(this, params, data)
          catch err
              reject err

module.exports = DataStormModel
