# A simple example to test endpoint with stormify
#
stormify = require '../src/stormify'

DS = stormify.DS
Bunyan = require 'bunyan'

log = new Bunyan
    name: 'sample-app'
    streams: [path: '/tmp/sample.log']



class TestController extends DS.Controller
    create: (data) ->
        @store.log.info 'ravi data', data
        super
    update: (data) ->
    destroy: ->


class TestModel extends DS.Model
    name: 'test'
    schema:
        message: DS.attr 'string', required:false


class TestDataStore extends DS
    constructor: (opts) ->
        super opts
        store = this

        @contains 'test',
            model: TestModel
            controller: TestController


port = 8080

{@app} = require('zappajs') port, ->
    
       @configure =>
           @use 'bodyParser', 'methodOverride', @app.router, 'static'
           @set 'basepath': '/v1.0'

       @configure
           development: => @use errorHandler: {dumpExceptions: on, showStack: on}
           production: => @use 'errorHandler'

       TDS = new TestDataStore
            auditor: log.child store: 'TestDataStore'
       stormify.serve.call @, TDS




