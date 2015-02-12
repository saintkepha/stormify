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

class YangRemoteProcedure extends YangObject


class YangClass extends StormClass
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
        @set storm: keyword
        @set name: name if name?
        @extend statics
        @include functions
    else
      class extends YangObject
        @set storm: keyword
        @extend statics
        @include functions

module.exports = YangClass
