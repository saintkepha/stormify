stormify = require '../../src/stormify'

DS = stormify.DS
Bunyan = require 'bunyan'
log = new Bunyan
    name:'studentdbms'
    streams: [ path: '/tmp/student-dbms.log' ]


SDS = stormify.createStore
    store: require './stores/student-data-store'
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


