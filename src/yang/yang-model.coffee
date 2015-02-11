DS = require '../data-storm'

class YangGrouping extends DS.Object

class YangContainer extends DS.Object

class YangExtension extends DS.Object

class YangProperty extends DS.Property

class YangListEntry extends DS.Object

class YangList extends YangProperty

  @Entry = YangListEntry
  constructor: (@model, opts, obj) -> super 'array', opts, obj

class YangModel extends DS.Model

  @meta = name: 'yang:model'

  @Grouping = YangGrouping
  @Container = YangContainer
  @List = YangList
  @Extension = YangExtension
  @Property = YangProperty

  serialize: (format='json') ->
    value = super 'json'
    for k, v of value
      prop = @getProperty k
      delete value[k] if prop.opts.private is true
    value

module.exports = YangModel
