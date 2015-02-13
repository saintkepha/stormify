StormClass = require '../storm/storm-class'
StormObject = require '../storm/storm-object'
YangModule = require './yang-module'

class YangObject extends StormObject

###*
# `YangGrouping` is purely a logical schema abstraction to allow
# "tagging" of sections of schema for reference use by other YANG
# schemas.
#
# So although we do create a `StormObject` mapping within the class
# hierarchy of the overall `YangModel`, it should not be directly
# referenced as property setter/getter.
####
class YangGrouping extends YangObject

class YangContainer extends YangObject

class YangExtension extends YangObject

class YangListEntry extends YangObject

class YangProperty extends YangObject.Property

class YangList extends YangProperty

  @Entry = YangListEntry
  constructor: (@model, opts, obj) -> super 'array', opts, obj

# yeah, this may be dangerous...
toSource = require 'tosource'
class YangRemoteProcedure extends YangObject

  @toSource: -> toSource @::exec if @::exec instanceof Function

  exec: -> throw new Error "cannot invoke RPC without function defined"

YangSpec = require './yang-core-spec-v1'
YangParser = require 'yang-parser'

assert = require 'assert'

class YangCoreEngine extends StormClass
  @set
    module:   YangModule
    grouping: YangGrouping
    container: YangContainer
    list: YangList
    extension: YangExtension
    leaf: YangProperty
    'leaf-list': YangProperty
    rpc: YangRemoteProcedure

  @define: (keyword, args) ->
    [ keyword, name ] = keyword.split ' '

    statics   = {}
    functions = {}
    for k, v of args
      if v instanceof Function
        functions[k] = v
      else
        statics[k] = v

    Override = (@get keyword)
    if Override? and Override.get? 'storm'
      class extends Override
        @set yang: keyword
        @set name: name if name?
        @extend statics
        @include functions
    else
      class extends YangObject
        @set yang: keyword
        @extend statics
        @include functions

  @generate: (schema, @parser=YangParser, @map=YangSpec) ->
    assert schema? and typeof schema is 'string',
      "must pass in input schema text to process for YANG"
    statement = @parser.parse schema
    assert statement? and statement.kw is 'module',
      "must pass in YANG module schema definition"

    # internal map of groupings (as well as those from imported)
    @groupings ?= {}
    @types ?= {}

    @processStatement statement

  @resolve: (grouping, props) ->
    unless @groupings.hasOwnProperty grouping
      console.log "WARNING: trying to 'uses' using #{grouping} identifier not found"
      return null

    # class extends @groupings[grouping]
    #   @extend  props.others
    #   @include props.storms
    @groupings[grouping]

  @processStatement: (statement, map=@map) ->
    # TODO: should handle prefix...
    { kw: keyword, arg: param, substmts: subs } = statement

    resolveMap = (map, key) =>
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

    map = resolveMap map, keyword

    if map?.type is 'array'
      hasMany = true # use later to validate cardinality
      map = map.value

    unless map?
      console.log "WARNING: unsupported YANG #{keyword} found, ignoring..."
      return

    # console.log "-> #{keyword}:#{param}"

    results = ((@processStatement statement, map) for statement in subs).filter (e) -> e? and e.value?

    unless results.length > 0
      return name: keyword, value: param

    properties = results.reduce ((a,b) -> a[b.name] = b.value; a), {}

    # if properties?
    #   console.log "<- #{keyword}:#{param} result:"
    #   console.log properties

    # special case to return the properties back for the module
    if keyword in [ 'module', 'submodule' ]
      # dynamically create a new Yang class definition
      return @define "#{keyword} #{param}", properties

    # TODO - this should lookup and include an external module into the
    # current generator's scope
    importModule  = (module, opts) -> null
    includeModule = (module, opts) ->


    value = switch keyword
      when 'import' then importModule param, properties
      when 'include' then includeModule param, properties

      # gets a copy of the 'grouping' named by param
      when 'uses' then @resolve param, properties

      when 'extension', 'grouping', 'rpc'
        @define "#{keyword} #{param}", properties

      else
        @define keyword, properties

    switch keyword
      when 'grouping' then @groupings[param] = value
      when 'extension'
        # TODO: should check if declared at top of the schema
        @map[param] = @map.container
      when 'typedef'
        # TODO: do something to make this new defintion available
        undefined

      when 'list' then value.set type: @define 'container', properties
      when 'leaf', 'leaf-list' then value.set type: properties.type

    return name: param, value: value

module.exports = YangCoreEngine
