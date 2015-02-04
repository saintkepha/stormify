DataStormObject = require './data-storm-object'

class RelationshipProperty extends DataStormObject.Property
    kind: null

    constructor: (@model, opts, obj) ->
        assert typeof model?.constructor is 'function',
            "cannot register a new relationship without proper model class"
        assert obj instanceof DataStormModel
            "cannot register a new relationship without containing obj defined"

        type = switch @kind
            when 'belongsTo' then 'object'
            when 'hasMany' then 'array'
        super type, opts, obj

        @modelName = @model.constructor.name

class BelongsToProperty extends RelationshipProperty
    kind: 'belongsTo'

    validate: -> super is true and @model::fetch @value instanceof @model

    get: -> @model::fetch super


class HasManyProperty extends RelationshipProperty
    kind: 'hasMany'

    validate: -> super is true and @value.every (e) => (@model::fetch e) instanceof @model

    get: -> (super.map (e) => @model::fetch e).filter (e) -> e?



class DataStormModel extends DataStormObject
    @belongsTo = (model, opts) -> new BelongsToProperty model, opts, this
    @hasMany   = (model, opts) -> new HasManyProperty model, opts, this
    @action    = (func, opts)  -> new ActionProperty func, opts, this

    # default schema for all DataStormModels
    id:         @attr 'any', defaultValue: -> (require 'node-uuid').v4()
    createdOn:  @attr 'date'
    modifiedOn: @attr 'date'
    accessedOn: @attr 'date'

    # this is a PRIVATE shared prototype hash map visible across ALL
    # model instances (intentionally undocumented)
    _models: {}

    constructor: (data, @container) ->
        super data
        @_name = @constructor.name
        @_id = @get('id')

        unless @_models.hasOwnProperty @_name
            @_models[@_name] =
                model: @constructor
                records: {}

    fetch: (id) -> @_models[@_name]?.records?[id]
    modelFor: (modelName) -> @_models[modelName]?.model

    getRelationships: ->
        (@everyProperty (key) -> this if this instanceof RelationshipProperty).filter (x) -> x?

    save: ->
        if @validate() is true
            @_models[@_name].records[@_id] = this

    destroy: -> delete @_models[@_name].records[@_id]

module.exports = DataStormModel
