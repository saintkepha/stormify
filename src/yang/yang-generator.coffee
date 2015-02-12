Yang = require './yang'

spec = require './yang-generator-map'
YangParser = require 'yang-parser'

YangGenerator = Yang.define 'module yang-generator',
  prefix: "yg"
  organization:
    "ClearPath Networks NFV R&D Group"

  contact: '''
    Web:  <http://www.clearpathnet.com>
    Code: <http://github.com/stormstack/stormify>

    Author: Peter K. Lee <mailto:plee@clearpathnet.com>
    '''

  description: """

      This module contains RPC extensions for enabling stormify
      enabled data storm endpoints to auto-generate new YANG schema
      based models into JavaScript class hierarchy and to dynamically
      derive REST-APIs to be served via 'stormify.express' mechanism.

      Using this generator, a YANG module schema definition file can
      be pushed to a stormify endpoint and that endpoint will auto
      construct the YANG module instance and be ready to accept REST
      API calls for manipulating the record properties and instances.

      This generator is a built-in module to stormify's data-storm
      module and usually the starting point before populating a
      stormify endpoint with data model records.

      """

  '2015-02-11': Yang.define 'revision',
    description: "Initial revision."
    reference: "Proprietary"

  generator: Yang.define 'container',
    description: "Conceptual container representing the generator"

    modules: Yang.define 'container',
      description: "Conceptual container showing all modules generated by this generator"

  'push-schema': Yang.define 'rpc',

    description: """

      Primary routine for issuing a request to push a YANG module
      schema to the stormify enabled endpoint.

      Responds with JSON converted representation of YANG module
      schema upon success

      """

    using: -> 'importSchema'

  ###
  # END OF YANG SCHEMA
  #
  # below contains custom routines for supporting the RPC operation
  ###

  importSchema: (schema) ->
    try
      module = @generate schema
      @_models.register module
      module.toJSON()
    catch err
      throw err

  generate: (schema, @parser=YangParser, @map=spec) ->
    @assert schema? and typeof schema is 'string',
      "must pass in input schema text to process for YANG"
    statement = @parser.parse schema
    @assert statement? and statement.kw is 'module',
      "must pass in YANG module schema definition"

    # internal map of groupings (as well as those from imported)
    @groupings ?= {}
    @processStatement statement

  resolve: (grouping, props) ->
    unless @groupings.hasOwnProperty grouping
      console.log "WARNING: trying to 'uses' using #{grouping} identifier not found"
      return null

    # class extends @groupings[grouping]
    #   @extend  props.others
    #   @include props.storms
    @groupings[grouping]

  processStatement: (statement, map=@map) ->
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
      return Yang.define "#{keyword} #{param}", properties

    # TODO - this should lookup and include an external module into the
    # current generator's scope
    importModule  = (module, opts) -> null
    includeModule = (module, opts) -> null

    value = switch keyword
      when 'import' then importModule param, properties
      when 'include' then includeModule param, properties

      # gets a copy of the 'grouping' named by param
      when 'uses' then @resolve param, properties

      when 'extension', 'grouping'
        Yang.define "#{keyword} #{param}", properties

      else
        Yang.define keyword, properties

    switch keyword
      when 'grouping' then @grouping[param] = value
      when 'extension'
        # TODO: extend the current map with 'container' substatements
        # @map["#{@['module-name']}:#{param}"] = @map.container
        # properties.meta = name: "#{@['module-name']}:#{param}"
        undefined
      when 'typedef'
        # TODO: do something to make this new defintion available
        undefined

      when 'list' then value.set type: Yang.define 'container', properties
      when 'leaf', 'leaf-list' then value.set type: properties.type

    return name: param, value: value

module.exports = YangGenerator
