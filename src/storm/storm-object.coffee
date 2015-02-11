Array::unique = ->
    return @ unless @length > 0
    output = {}
    for key in [0..@length-1]
      val = @[key]
      switch
          when typeof val is 'object' and val.id?
              output[val.id] = val
          else
              output[val] = val
    #output[@[key]] = @[key] for key in [0...@length]
    value for key, value of output

Array::contains = (query) ->
    return false if typeof query isnt "object"
    hit = Object.keys(query).length
    @some (item) ->
        match = 0
        for key, val of query
            match += 1 if item[key] is val
        if match is hit then true else false

Array::where = (query) ->
    return [] if typeof query isnt "object"
    hit = Object.keys(query).length
    @filter (item) ->
        match = 0
        for key, val of query
            match += 1 if item[key] is val
        if match is hit then true else false

Array::without = (query) ->
    return @ if typeof query isnt "object"
    @filter (item) ->
        for key,val of query
            return true unless item[key] is val
        false # item matched all query params

Array::pushRecord = (record) ->
    return null if typeof record isnt "object"
    @push record unless @contains(id:record.id)

class PropertyValidationError extends Error

class StormClass
  @extend:  (obj) ->
    @[k] = v for k, v of obj
    this
  @include: (obj) ->
    @::[k] = v for k, v of obj
    this

  # everyone should have this...
  assert: require 'assert'

class StormProperty extends StormClass
  kind: 'attr'

  constructor: (@type, @opts={}, @obj) ->
    @assert @obj instanceof StormObject,
        "cannot register a new property without a reference to an object it belongs to"

    @opts.required ?= false
    @opts.unique ?= false

    ###*
    # @property value
    ###
    @value = undefined
    ###*
    # @property isDirty
    # @default false
    ###
    @isDirty = false

  get: -> if @value instanceof StormProperty then @value.get() else @value

  set: (value, opts={}) ->
    # console.log "setting #{@constructor.name} of type: #{@type} with:"
    # console.log value
    ArrayEquals = (a,b) -> a.length is b.length and a.every (elem, i) -> elem is b[i]

    value ?= switch
      when typeof @opts.defaultValue is 'function' then @opts.defaultValue.call @obj
      else @opts.defaultValue

    cval = @value
    nval = @normalize value

    # console.log "set() normalized new value: #{nval}"
    # console.log nval

    if nval instanceof Array and nval.length > 0
      nval = (nval.filter (e) -> e?)
      nval = nval.unique() if @opts.unique is true

    # if nval instanceof StormProperty
    #   opts.skipValidation = true

    # console.log "set() validating new value: #{nval}"
    # console.log nval

    unless opts.skipValidation is true or @validate nval
        return new PropertyValidationError nval

    @isDirty = switch
      when not cval? and nval? then true
      when @type is 'array' then not ArrayEquals cval, nval
      when cval is nval then false
      else true
    @value = nval if @isDirty is true

    #console.log "set() isDirty: #{@isDirty} and value: #{@value}"
    this

  validate: (value=@value) ->
    # execute custom validator if available
    if typeof @opts.validator is 'function'
      return (@opts.validator.call @obj, value)

    unless value?
      return (@opts.required is false)

    if value instanceof StormProperty
      value = value.get()

    switch @type
      when 'string' or 'number' or 'boolean' or 'object'
        typeof value is @type
      when 'date'
        value instanceof Date
      when 'array'
        value instanceof Array
      else
        true

  normalize: (value) ->
    switch
      when value instanceof Object and typeof value.stormify is 'function'
        # a special case, returns new form of StormProperty
        value.stormify.call @obj
      when @type is 'date' and typeof value is 'string'
        new Date value
      when @type is 'array' and not (value instanceof Array)
        if value? then [ value ] else []
      else
        value

  serialize: (format='json') ->
    switch
      when typeof @opts.serializer is 'function'
        @opts.serializer.call @obj, @value, format
      when @value instanceof StormProperty
        @value.serialize format
      else
        @value

class ComputedProperty extends StormProperty
  kind: 'computed'
  ###*
  # @property func
  # @default null
  ###
  @func = -> null

  constructor: (@func, opts={}, obj) ->
    @assert typeof @func is 'function',
      "cannot register a new ComputedProperty without a function"
    type = opts.type ? 'computed'
    super type, opts, obj
    @cache = opts.cache ? 0
    @cachedOn = new Date() if @cache > 0

  isCachedValid: -> @cache > 0 and (new Date() - @cachedOn)/1000 < @cache

  get: ->
    unless @value? and @isCachedValid()
      # XXX - handle @opts.async is 'true' in the future (return a Promise)
      @set (@func.call @obj)
      @cachedOn = new Date() if @cache > 0
    super

  serialize: -> super @get()

class StormObject extends StormClass
  #@attr      = (type, opts) -> stormify: -> new StormProperty type, opts, this
  #@computed  = (func, opts) -> stormify: -> new ComputedProperty func, opts, this

  @attr = (type, opts) ->
    class extends StormProperty
      @extend type: type, opts: opts

  @computed  = (func, opts) ->
    class extends ComputedProperty
      @extend type: func, opts: opts

  @Property = StormProperty
  @ComputedProperty = ComputedProperty

  constructor: (data, @opts={}) ->
    @_properties = {}
    for key, val of this when key isnt 'constructor' and val instanceof Function and val.name is '_Class'
      @addProperty key, (new val val.type, val.opts, this) # (val.stormify.call this)

    # initialize all properties to defaultValues
    @everyProperty (key) -> @set undefined, skipValidation: true
    (@set data, skipValidation: true) if data?

  keys: -> Object.keys @_properties

  addProperty: (key, property) ->
    if not (@hasProperty key) and property instanceof StormClass
      @_properties[key] = property
    property

  removeProperty: (key) -> delete @_properties[key] if @hasProperty key
  getProperty: (key) -> @_properties[key] if @hasProperty key
  hasProperty: (key) -> @_properties.hasOwnProperty key

  get: (keys...) ->
    result = {}
    switch
      when keys.length is 0
        @everyProperty (key) -> result[key] = @get()
      when keys.length is 1
        result = (@getProperty keys[0])?.get()
      else
        result[key] = (@getProperty key)?.get() for key in keys
    result

  ###*
  # `set` is used to place values on matching StormProperty
  # instances. Accepts an object of key/values
  #
  # obj.set hello:'world'
  #
  # { hello: 'world' }
  ###
  set: (obj, opts) ->
    return unless obj instanceof Object
    ((@getProperty key)?.set value, opts) for key, value of obj
    this # make it chainable

  everyProperty: (func) -> (func?.call prop, key) for key, prop of @_properties

  validate: -> (@everyProperty (key) -> name: key, isValid: @validate()).filter (e) -> e.isValid is false

  serialize: (format='json') ->
    o = switch format
      when 'json' then {}
      else ''
    @everyProperty (key) ->
      switch format
        when 'json' then o[key] = @serialize format
        when 'xml' then o += "<#{key}>" + (@serialize format) + "</#{key}>"
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

module.exports = StormObject
