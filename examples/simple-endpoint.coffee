# A simple example to test endpoint with stormify
#
stormify = require '../src/stormify'

DS = stormify.DS
Bunyan = require 'bunyan'

log = new Bunyan
    name: 'sample-app'
    streams: [path: '/tmp/sample.log']


class TestModel extends DS.Model
    name: 'test'
    schema:
        message: DS.attr 'string'


class TestDataStore extends DS
    constructor: (opts) ->
        super opts
        store = this

        @contains 'test',
            model: TestModel
            serveOverride: true
            serve: (opts) ->
                baseUrl = opts?.baseUrl or ''
                @post '/test': ->
                    console.log @req.body
                    return @send @req.body


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




