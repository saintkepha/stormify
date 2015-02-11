
data1 = '''
 module example-jukebox {

   namespace "http://example.com/ns/example-jukebox";
   prefix "jbox";
   import ietf-restconf { prefix rc; }
 }
'''

data2 = '''
module acme-system {
     namespace "http://acme.example.com/system";
     prefix "acme";

     organization "ACME Inc.";
     contact "joe@acme.example.com";
     description
         "The module for entities implementing the ACME system.";

     revision 2007-06-09 {
         description "Initial revision.";
     }

     container system {
         leaf host-name {
             type string;
             description "Hostname for this system";
         }

         leaf-list domain-search {
             type string;
             description "List of domain names to search";
         }

         container login {
             leaf message {
                 type string;
                 description
                     "Message given at start of login session";
             }

             list user {
                 key "name";
                 leaf name {
                     type string;
                 }
                 leaf full-name {
                     type string;
                 }
                 leaf class {
                     type string;
                 }
             }
         }
     }
 }
'''

YS = require '../src/yang/yang-storm'

storm = new YS

result = storm.import data1
# console.log result?.serialize()
# console.log result?._models.serialize()

result = storm.import data2
# console.log result?.serialize()
# console.log result?._models.serialize()

result = storm.import 'https://raw.githubusercontent.com/netconf-wg/restconf/master/ietf-restconf.yang'

data1 = '''
 module example-jukebox {

   namespace "http://example.com/ns/example-jukebox";
   prefix "jbox";
   import ietf-restconf { prefix rc; }
 }
'''

data2 = '''
module acme-system {
     namespace "http://acme.example.com/system";
     prefix "acme";

     organization "ACME Inc.";
     contact "joe@acme.example.com";
     description
         "The module for entities implementing the ACME system.";

     revision 2007-06-09 {
         description "Initial revision.";
     }

     container system {
         leaf host-name {
             type string;
             description "Hostname for this system";
         }

         leaf-list domain-search {
             type string;
             description "List of domain names to search";
         }

         container login {
             leaf message {
                 type string;
                 description
                     "Message given at start of login session";
             }

             list user {
                 key "name";
                 leaf name {
                     type string;
                 }
                 leaf full-name {
                     type string;
                 }
                 leaf class {
                     type string;
                 }
             }
         }
     }
 }
'''

YG = new YangGenerator

module = YG.generate data2
jukebox = new module
console.log jukebox.serialize()

# module = YG.generate data2
# console.log module

###*
# `generate` takes in input (text or YangStatements) and returns resolved YangModel
#
# NOTE: will need some refactoring/cleanup
###

###
generate = (input, context=yang, module) ->
  if typeof input is 'string'
    schema = input
    input = .parse input
    assert input? and input.kw is 'module',
      "cannot process input text as YANG module definition"

    # dynamically create a new YangModel instance for the module
    model = class extends YangModel
      @extend 'meta-name': input.kw, 'yang-schema': schema
    module = new model

  yin = context[input.kw]
  subs = switch
    when yin instanceof Function
      yin()
    when yin instanceof Array
      type = 'array'
      if yin[0] instanceof Function
        yin[0]()
      else
        yin[0]
    else yin

  switch
    when not subs?
      console.log "WARNING: unsupported YANG keyword '#{input.kw}' got #{yin}"
      #console.log context
      return yin
    when typeof subs is 'string'
      return subs

  switch input.kw
    when 'import'
      console.log "importing... #{input.arg}"
      instance = module.find input.arg
      assert instance? and instance instanceof YangModel,
        "ERROR: unable to import YANG module #{input.arg}"
      # TODO - here we need to do something about the instance properties being accessible

    when 'leaf', 'leaf-list', 'revision'
      opts = {}
      for statement in input.substmts
        opts[statement.kw] = statement.arg
      return opts

  unless input.substmts.length > 0
    return input.arg

  pDefs = {}
  pVals = {}
  for statement in input.substmts
    { kw: keyword, arg: param } = statement

    unless (subs.hasOwnProperty keyword) then continue
    assert (subs.hasOwnProperty keyword),
      "invalid YANG #{keyword} found within #{input.kw}"

    console.log "-> #{keyword} with #{Object.keys(statement)} options"
    value = generate statement, subs, module
    console.log "<- #{keyword} resolved to " + value

    key = switch keyword
      when 'container','grouping','leaf','leaf-list','list' then param
      else keyword

    pDefs[key] = switch
      when value instanceof YangModel
        pVals[key] = value
        if subs[keyword] instanceof Array
          YangModel.hasMany value.constructor, embedded:true
        else
          YangModel.belongsTo value.constructor
      when key is 'revision'
        pVals[key] = param
        YangModel.attr 'date', value
      when typeof value?.type is 'string'
        type = switch keyword
          when 'leaf-list' then 'array'
          else value.type
        YangModel.attr type, value
      else
        pVals[key] = param
        YangModel.attr value

  # dynamically construct a new class definition
  metaName = "#{module.get('meta-name')}:#{input.kw}:#{input.arg}"

  console.log "making a new YangModel for #{metaName}"

  model = class extends YangModel
    @extend 'meta-name': metaName, 'yang-schema': schema
    @include pDefs

  new model pVals
###
