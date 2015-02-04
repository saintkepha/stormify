
class PropertyValidationError extends Error

class DataStormProperty
    ###*
    # @property value
    ###
    value: undefined

    ###*
    # @property isDirty
    # @default false
    ###
    isDirty: false

    constructor: (@type, @opts, @obj) ->
        assert obj instanceof DataStormObject,
            "cannot register a new property without a reference to an object it belongs to"
        @opts ?= required: false
        @value = [] if @type is 'array'

    get: ->
        @value ?= switch
            when typeof @opts.defaultValue is 'function' then @opts.defaultValue.call @obj
            else @opts?.defaultValue

        if typeof @value is 'array'
            @value = (@value.filter (e) -> e?)
            @value = @value.unique() if @opts.unique is true

        return new PropertyValidationError @value unless @validate()

        @value

    set: (value) ->
        ArrayEquals = (a,b) -> a.length is b.length and a.every (elem, i) -> elem is b[i]

        cval = @value
        nval = switch @type
            when 'date' and typeof value is 'string'
                new Date value
            when 'array' and typeof value isnt 'array'
                if value? then [ value ] else []
            else
                value

        @isDirty = switch
            when @type is 'array' then not ArrayEquals cval, nval
            when cval is nval then false
            else true
        @value = nval

        @obj # return object containing this property to allow chaining

    validate: ->
        # we shouldn't allow validator to return value?
        if typeof @opts.validator is 'function'
            @value = @opts.validator.call @obj, @value

        unless @value? and @opts.required is true
            return false

        switch @type
            when 'string' or 'number' or 'boolean' or 'object'
                typeof @value is @type
            when 'date'
                @value instanceof Date
            when 'array'
                @value instanceof Array
            else
                true

class ComputedProperty extends DataStormProperty
    ###*
    # @property func
    # @default null
    ###
    @func = -> null

    constructor: (@func, opts, obj) ->
        assert typeof func is 'function',
            "cannot register a new ComputedProperty without a function"
        type = opts?.type ? 'computed'
        super type, opts, obj
        @cachedOn = new Date() if opts.cache > 0

    isCachedValid: -> @opts.cache > 0 and (new Date() - @cachedOn)/1000 < @opts.cache

    get: ->
        unless @value? or @isCachedValid()
            # XXX - handle @opts.async is 'true' in the future (return a Promise)

            @value = @func.call @obj
            @cachedOn = new Date() if @opts.cache > 0
        super


class DataStormObject
    @attr      = (type, opts) -> new DataStormProperty type, opts, this
    @computed  = (func, opts) -> new ComputedProperty func, opts, this

    @Property = DataStormProperty

    @assert = require 'assert'
    @extend = require('util')._extend

    _properties: {}

    constructor: (data) ->
        p = @extend {}, this.constructor.prototype
        @_properties[key] = p[key] for key in Object.keys(p) when p[key] instanceof DataStormProperty
        @setProperties data if data?

    get: (keyName, opts) -> @_properties[keyName]?.get opts
    set: (keyName, value, opts) -> @_properties[keyName]?.set value, opts

    everyProperty: (func) -> func?.call(prop, key) for key, prop of @_properties

    validate: -> @everyProperty (key) -> name: key, isValid: @validate()

    setProperties: (obj) ->
        return unless obj instanceof Object
        @set key, value for key, value of obj

    getProperties: (keys) ->
        o = {}
        unless keys? and keys instanceof Array
            @everyProperty (key) -> o[key] = @get()
        else
            o[key] = @get key for key in keys when typeof key is 'string' or typeof key is 'number'
        o

    clearDirty: -> @everyProperty -> @isDirty = false
    dirtyProperties: (keys) -> (@everyProperty (key) -> @isDirty ? key).filter (x) ->
        if keys? then x? and x in keys else x?
    isDirty: (keys) ->
        keys = [ keys ] if keys? and keys not instanceof Array
        (@dirtyProperties keys).length > 0

        ### for future optimization reference
        dirty = @dirtyProperties().join ' '
        keys.some (prop) -> ~dirty.indexOf prop
        ###

module.exports = DataStormObject
