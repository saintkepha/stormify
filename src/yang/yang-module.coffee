StormModel  = require '../storm/storm-model'

spec = require './yang-core-spec-v1'

class YangModule extends StormModel
  @set yang: 'module'

  @toYANG: ->
    convert = (json, offset=0) ->
      return json unless json instanceof Object
      res = ''
      for k, v of json when spec.hasOwnProperty (k.split ':')[0]
        res += (Array(offset).join ' ') + k.replace(':',' ') + ' '
        unless v instanceof Object
          res += switch k
            when 'contact', 'description', 'reference', 'organization'
              v = '\n"'+v
              v = v.replace /\n/g, '\n' + Array(offset+2).join ' '
              v + '";\n\n'
            when 'namespace', 'prefix'
              '"' + v + '";\n'
            else
              v + ';\n'
        else
          res += "{\n"
          res += (convert v, offset+2)
          res += (Array(offset).join ' ') + "}\n\n"
      res
    convert @toJSON 'yang', true

  constructor: ->
    super
    # a simple name remapping
    @_modules = @_models
    this

  serialize: (format='json') ->
    o = {}
    prefix = @constructor.get 'name'
    @everyProperty (key) ->
      # unless this instanceof YangObject or this instanceof YangProperty
      #   return
      value = @serialize()
      return unless value?
      o[prefix+':'+key] = value
    o

  # invoke: (rpc, args...) ->
  #   super

module.exports = YangModule
