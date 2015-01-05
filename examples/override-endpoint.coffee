stormify = require '../src/stormify'
DS = stormify.DS
Bunyan = require 'bunyan'
log = new Bunyan
    name:'simple-endpoint'
    streams: [ path: '/tmp/simple-endpoint.log' ]


#Model Definition
class StudentModel extends DS.Model
    name: 'student'
    schema:
        name:       DS.attr 'string', required: true                
        age:        DS.attr 'number', required: true
        address:    DS.attr 'string', required: true                          


#Store Definiton
class StudentDataStore extends DS
    name: "student-ds"
    constructor: (opts) ->
        super opts
        store = this

        @contains 'students',
            model: StudentModel    
            serveOverride: true
            serve: (opts) ->
                baseUrl = opts?.baseUrl or ''
                @post '/students': ->
                    console.log @req.body
                    return @send @req.body    
        @initialize()   

#create a dataStore
SDS = stormify.createStore
    store: StudentDataStore
    auditor: log.child store: 'student-ds'

port = 8080

{@app} = require('zappajs') port, ->

    @configure =>
        @use 'bodyParser', 'methodOverride', @app.router, 'static'
        @set 'basepath': '/v1.0'

    @configure
      development: => @use errorHandler: {dumpExceptions: on, showStack: on}
      production: => @use 'errorHandler'

    stormify.serve.call @, SDS


