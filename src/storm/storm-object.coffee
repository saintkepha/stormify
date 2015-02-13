StormClass = require './storm-class'

class PropertyValidationError extends Error

class StormProperty extends StormClass
  @set storm: 'property'

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
  @set storm: 'computed'

  kind: 'computed'
  ###*
  # @property func
  # @default null
  ###
  @func = -> null

  constructor: (@func, opts={}, obj) ->
    console.log 'computed'
    console.log @func
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
  @set storm: 'object'

  @attr = (type, opts) ->
    class extends StormProperty
      @set type: type, opts: opts

  @computed  = (func, opts) ->
    class extends ComputedProperty
      @set type: func, opts: opts

  @Property = StormProperty
  @ComputedProperty = ComputedProperty

  constructor: (data, @opts={}, @container) ->
    @_properties = {}
    for key, StormForm of this when key isnt 'constructor' and StormForm?.meta?.storm?
      input = switch (StormForm.get 'storm')
        when 'object' then 'data'
        else 'type'

      @addProperty key, (new StormForm (StormForm.get input), (StormForm.get 'opts'), this)

    # initialize all properties to defaultValues
    @everyProperty (key) -> @set undefined, skipValidation: true
    (@set data, skipValidation: true) if data?

  keys: -> Object.keys @_properties

  addProperty: (key, property) ->
    if not (@hasProperty key) and property instanceof StormClass
      @_properties[key] = property
    property

  removeProperty: (key) -> delete @_properties[key] if @hasProperty key
  hasProperty: (key) -> @_properties.hasOwnProperty key

  ###*
  # `getProperty` supports retrieving property based on composite key such as:
  # 'hello.world.bye'
  #
  # Since this routine is the primary function for get/set operations,
  # you can also use it to specify nested path during those operations.
  ###
  getProperty: (key) ->
    return unless key?
    composite = key?.split '.'
    key = composite.shift()
    prop = @_properties[key] if @hasProperty key
    for key in composite
      return unless prop?
      prop = prop.getProperty? key
    prop

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
  #
  # obj.set test:'a', sample:'b'
  #
  # obj.set 'test.nested.param':'a', sample:'b'
  #
  # also takes in `opts` as an optional param object to override
  # validations and other special considerations during the `set`
  # execution.
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
