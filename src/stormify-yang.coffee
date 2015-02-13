Yang = require './yang/yang-core'

Promise = require 'promise'

###*
# `YangStorm` - provides ability to manage data models purely based on
# schemas.  Does not handle any management of instantiated data model
# records.  For data records collections and relationships management,
# please refer to `DataStorm`.
###
YangStorm = Yang.define 'module stormify-yang',
  prefix: "stormy"
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

    This generator is a built-in capability to stormify framework
    and usually the starting point before populating a target
    endpoint with data model records and associated RPC functions.

    """

  '2015-02-05': Yang.define 'revision',
    description: "Initial revision."
    reference: "Proprietary"

  'stormify-data': Yang.define 'include'

  modules: Yang.define 'container',
    description: "Conceptual container showing all modules managed by this module"

    # a special override to the container upon a get request
    get: -> @container._modules
    serialize: -> @get().serialize()

  'import-schema': Yang.define 'rpc',

    description: """

      Primary routine for executing a request to import a YANG module
      schema to the target endpoint.

      Responds with JSON converted representation of YANG module
      schema upon success.

      """

    exec: -> @importSchema.apply this, arguments

  'export-schema': Yang.define 'rpc',

    description: """

      Primary routine for executing a request to export YANG module
      schema from the target endpoint.

      Responds with YANG or JSON representation of matching YANG
      module's schema upon success depending on the specified HTTP
      header.

      """

    exec: -> @exportSchema.apply this, arguments

  'import-rpc': Yang.define 'rpc',

    description: """

      Secondary routine for executing a request to import JS code
      functions representing RPC functionality to a previously
      imported YANG schema.

      This operation should only take place between trusted systems
      since it is possible arbitrary function can be executed,
      including crashing the receiving system.

      No attempt will be made to qualify the code being pushed.

      The input format MUST be JSON-formatted containing JS
      represented in string format as follows:

      {
        module: 'some-name',
        rpc: {
          'rpc-name-1': 'function (hello) { return hello; }',
          'rpc-name-2': 'function (bye) { return bye; }'
        }
        override: true/false
      }

      The function(s) will be merged into the target module if found
      to have been auto-generated via a prior 'push-schema' rpc call.

      The function(s) will have access to all the pre-existing
      functions within the module's instance space.  For details, be
      sure to review/understand the stormify data-storm class
      hierarchy for traversing/accessing properties within the given
      module.

      """

    exec: -> @importRPC.apply this, arguments

  'export-rpc': Yang.define 'rpc',

    description: """

      Secondary routine for executing a request to export JS code
      functions representing RPC functionality from a previously
      imported YANG schema.

    """

    exec: -> @exportRPC.apply this, arguments


  ###
  # END OF YANG SCHEMA
  #
  # below contains custom routines for supporting the RPC operation
  ###

  importSchema: (payload, encoding='yang') ->
    new Promise (resolve, reject) =>
      unless typeof payload is 'string'
        if /\b((?=[a-z0-9-]{1,63}\.)(xn--)?[a-z0-9]+(-[a-z0-9]+)*\.)+[a-z]{2,63}\b/.test(payload.url)
          needle = (require 'needle')
          needle.get payload.url, (err, res) =>
            Module = Yang.generate res.body
            @_modules.register Module
            resolve Module
        else reject 'invalid url'
      else
        Module = Yang.generate payload
        @_modules.register Module
        resolve Module

  exportSchema: (payload, encoding='yang') ->
    try
      target = payload?.module ? payload
      Module = (@_modules.contains target).model
      switch encoding
        when 'yang' then Module.toYANG()
        when 'json' then Module.toJSON 'yang'
    catch err
      console.log "WARNING: unable to retrieve schema from requested module: #{target}"
      throw err

  importRPC: (payload) ->
    try
      target = payload?.module ? payload
      Module = (@_modules.contains target).model
      for k, v of payload.rpc
        RemoteProcedure = Module::[k]
        continue unless (RemoteProcedure.get 'yang') is 'rpc'

        if RemoteProcedure::exec instanceof Function
          unless payload.override is true
            throw new Error "attempting to import over pre-existing RPC definition"

        RemoteProcedure.include exec: eval "(#{v})" # wrap for functions
    catch err
      console.log "WARNING: unable to import RPC to requested module: #{target}"
      throw err

  exportRPC: (payload) ->
    try
      target = payload?.module ? payload
      Module = (@_modules.contains target).model
      reply = rpc: {}
      for k, v of Module.prototype when (v.get? 'yang') is 'rpc'
        reply.rpc[k] = v.toSource()
      reply
    catch err
      console.log "WARNING: unable to export RPC from requested module: #{target}"
      throw err

module.exports = YangStorm
