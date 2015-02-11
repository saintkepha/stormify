assert = require 'assert'

YangModel = require './yang-model'

class YangGenerator

  spec = require './yang-generator-map'
  YangParser = require 'yang-parser'

  constructor: (@parser=YangParser) -> this

  generate: (schema, @map=spec) ->
    assert schema? and typeof schema is 'string',
      "must pass in input schema text to process for YANG"
    statement = @parser.parse schema
    assert statement? and statement.kw is 'module',
      "must pass in YANG module schema definition"

    # internal map of groupings (as well as those from imported)
    @groupings = {}

    #@['module-name'] = statement.arg
    generator = this
    # dynamically create a new YangModel class definition
    class extends YangModel
      @extend meta: name: statement.arg, schema: schema
      @include (generator._process statement)

  # TODO - this should lookup and include an external module into the
  # current generator's scope
  import: (module, opts) -> null
  include: (module, opts) -> null

  resolve: (grouping, opts) ->
    unless @groupings.hasOwnProperty grouping
      console.log "WARNING: trying to 'uses' using #{grouping} identifier not found"
      return null

    class extends @groupings[grouping]
      @include opts

  _resolveMap: (map, key) ->
    value = map[key] ? @map[key] # the latter is for namespace that got changed afterwards
    switch
      when value instanceof Function then value()
      when value instanceof Array
        v = value[0]
        v = switch
          when v instanceof Function then v()
          else v
        type: 'array'
        value: v
      else value

  _process: (statement, map=@map, context) ->
    # TODO: should handle prefix...
    { kw: keyword, arg: param, substmts: subs } = statement

    map = @_resolveMap map, keyword

    if map?.type is 'array'
      hasMany = true # use later to validate cardinality
      map = map.value

    unless map?
      console.log "WARNING: unsupported YANG #{keyword} found for #{context}"
      return

    #console.log "-> #{keyword}:#{param}"

    results = ((@_process substatement, map, statement) for substatement in subs)
    properties = (results.filter (e) -> e?).reduce ((a,b) -> a[b.name] = b.value; a), {} if results.length > 0

    # if properties?
    #   console.log "<- #{keyword}:#{param} result:"
    #   console.log properties

    return switch keyword
      # special case to return the properties back for the module
      when 'module','submodule' then properties

      when 'import' then @import param, properties
      when 'include' then @include param, properties

      # gets a copy of the 'grouping' named by param
      when 'uses' then name: param, value: @resolve param, properties

      when 'typedef'
        # TODO: do something to make this new defintion available
        null

      when 'extension'
        # TODO: extend the current map with 'container' substatements
        # @map["#{@['module-name']}:#{param}"] = @map.container
        # properties.meta = name: "#{@['module-name']}:#{param}"
        name: param
        value: class extends YangModel.Extension
          @extend properties

      when 'grouping'
        # save this grouping for latter lookup
        group = class extends YangModel.Grouping
          @extend meta: name: "#{@['module-name']}:#{param}"
          @include properties
        @groups[param] = group
        name: param
        value: group

      when 'container'
        name: param
        value: class extends YangModel.Container
          @include properties

      when 'list'
        name: param
        value: class extends YangModel.List
          @extend
            type: class extends YangModel.List.Entry
              @include properties
            opts: properties

      when 'revision'
        properties.defaultValue = param
        name: keyword
        value: class extends YangModel.Property
          @extend opts: properties

      when 'rpc'
        # rpc not supported yet
        null

      else
        # non-nested nodes (leaf, leaf-list, etc.)
        if properties?
          name: param
          value: class extends YangModel.Property
            @extend type: properties.type, opts: properties
        else name: keyword, value: param

module.exports = YangGenerator
