###*
# `yang` lexical parsing map for dealing with keyword namespaces along
# with cardinal relationship enforcements
###
yang =
  module: ->
    anyxml: [ yang.anyxml ]
    augment: [ yang.augment ]
    choice: [ yang.choice ]
    contact: yang.contact
    container: [ yang.container ]
    description: yang.description
    deviation: [ yang.deviation ]
    extension: [ yang.extension ]
    feature: [ yang.feature ]
    grouping: [ yang.grouping ]
    identity: [ yang.identity ]
    import: [ yang.import ]
    include: [ yang.include ]
    leaf: [ yang.leaf ]
    'leaf-list': [ yang['leaf-list'] ]
    list: [ yang.list ]
    namespace: 'uri'
    notification: [ yang.notification ]
    organization: yang.organization
    prefix: 'string'
    reference: yang.reference
    revision: [ yang.revision ]
    rpc: [ yang.rpc ]
    typedef: [ yang.typedef ]
    uses: [ yang.uses ]
    'yang-version': yang['yang-version']

  anyxml: null # not supported!

  augment: null # not yet supported (7.15.1)

  choice: null # not yet supported!

  config: 'boolean' # (7.19.1)

  contact: 'string'

  container: ->
    anyxml: [ yang.anyxml ]
    choice: [ yang.choice ]
    config: yang.config
    container: [ yang.container ]
    description: yang.description
    grouping: [ yang.grouping ]
    'if-feature': [ yang['if-feature'] ]
    leaf: [ yang.leaf ]
    'leaf-list': [ yang['leaf-list'] ]
    list: [ yang.list ]
    must: [ yang.must ]
    presence: 'string'
    reference: yang.reference
    status: yang.status
    typedef: [ yang.typedef ]
    uses: [ yang.uses ]
    when: yang.when

  description: 'string'

  deviation: null # not yet supported (7.18.3.1)

  extension: ->
    argument: ->
      'yin-element': 'boolean'
    description: yang.description
    reference: yang.reference
    status: yang.status

  feature: ->
    description: yang.description
    'if-feature': [ yang['if-feature'] ]
    reference: yang.reference
    status: yang.status

  grouping: (key, subs) ->
    anyxml: [ yang.anyxml ]
    choice: [ yang.choice ]
    container: [ yang.container ]
    description: yang.description
    grouping: [ yang.grouping ]
    leaf: [ yang.leaf ]
    'leaf-list': [ yang['leaf-list'] ]
    list: [ yang.list ]
    reference: yang.reference
    status: yang.status
    typedef: [ yang.typedef ]
    uses: [ yang.uses ]

  identity: ->
    base: 'string'
    description: yang.description
    reference: yang.reference
    status: yang.status

  'if-feature': 'string'

  include: (key, subs) ->
    'revision-date': 'date'

  import: (key, subs) ->
    prefix: 'string'
    'revision-date': 'date'

  leaf: (key, subs) ->
    config: yang.config
    default: 'string'
    description: yang.description
    'if-feature': [ yang['if-feature'] ]
    mandatory: 'boolean'
    must: [ yang.must ]
    reference: yang.reference
    status: yang.status
    type: yang.type # required
    units: 'string'
    when: yang.when

  'leaf-list': (key, subs) ->
    config: yang.config
    description: yang.description
    'if-feature': [ yang['if-feature'] ]
    'max-elements': 'number'
    'min-elements': 'number'
    must: [ yang.must ]
    'ordered-by': 'string' # system (default) or user
    reference: yang.reference
    status: yang.status
    type: yang.type # required
    units: 'string'
    when: yang.when

  list: ->
    anyxml: [ yang.anyxml ]
    choice: [ yang.choice ]
    config: yang.config
    container: [ yang.container ]
    description: yang.description
    grouping: [ yang.grouping ]
    'if-feature': [ yang['if-feature'] ]
    key: 'string' # need to review 7.8.2 further
    leaf: [ yang.leaf ]
    'leaf-list': [ yang['leaf-list'] ]
    list: [ yang.list ]
    'max-elements': 'number'
    'min-elements': 'number'
    must: [ yang.must ]
    'ordered-by': 'string' # system (default) or user
    reference: yang.reference
    status: yang.status
    typedef: [ yang.typedef ]
    unique: 'string' # space-separated list of constraints
    uses: [ yang.uses ]
    when: yang.when

  must: ->
    description: yang.description
    'error-app-tag': 'string'
    'error-message': 'string'
    reference: yang.reference

  notification: null # not yet supported! (7.14.1)

  organization: 'string'

  reference: 'string'

  revision: ->
    description: yang.description
    reference: yang.reference

  rpc: ->
    description: yang.description
    grouping: [ yang.grouping ]
    'if-feature': [ yang['if-feature'] ]
    input: ->
      anyxml: [ yang.anyxml ]
      choice: [ yang.choice ]
      container: [ yang.container ]
      grouping: [ yang.grouping ]
      leaf: [ yang.leaf ]
      'leaf-list': [ yang['leaf-list'] ]
      list: [ yang.list ]
      typedef: [ yang.typedef ]
      uses: [ yang.uses ]
    output: yang.rpc.input
    reference: yang.reference
    status: yang.status
    typedef: [ yang.typedef ]

  status: 'string' # current/deprecated/obsolete

  submodule: (key, subs) ->
    anyxml: [ yang.anyxml ]
    augment: [ yang.augment ]
    'belongs-to': ->
      prefix: 'string'
    choice: [ yang.choice ]
    contact: yang.contact
    container: [ yang.container ]
    description: yang.description
    deviation: [ yang.deviation ]
    extension: [ yang.extension ]
    feature: [ yang.feature ]
    grouping: [ yang.grouping ]
    identity: [ yang.identity ]
    import: [ yang.import ]
    include: [ yang.include ]
    leaf: [ yang.leaf ]
    'leaf-list': [ yang['leaf-list'] ]
    list: [ yang.list ]
    namespace: 'uri'
    notification: [ yang.notification ]
    organization: yang.organization
    prefix: 'string'
    reference: yang.reference
    revision: [ yang.revision ]
    rpc: [ yang.rpc ]
    typedef: [ yang.typedef ]
    uses: [ yang.uses ]
    'yang-version': yang['yang-version']

  type: ->
    bit: [ yang.bit ] # for type.bits
    enum: [ yang.enum ] # for type.enumeration
    length: 'number'
    path: 'string'
    pattern: [ 'string' ] # regex or string... missing substatements! (9.4.6.1)
    range: 'string' # need to support substatements! (9.2.4.1)
    'require-instance': 'number'
    type: [ yang.type ]

  bit: ->
    description: yang.description
    reference: yang.reference
    status: yang.status
    position: 'number'

  enum: ->
    description: yang.description
    reference: yang.reference
    status: yang.status
    value: 'number'

  typedef: ->
    default: 'string'
    description: yang.description
    units: 'string'
    type: yang.type
    reference: yang.reference

  uses: ->
    augment: yang.augment
    description: yang.description
    'if-feature': [ yang['if-feature'] ]
    refine: -> null # not yet supported! (7.12.2)
    reference: yang.reference
    status: yang.status
    when: yang.when

  when: 'xpath'

module.exports = yang
