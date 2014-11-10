assert = require 'assert'

Array::unique = ->
      output = {}
      output[@[key]] = @[key] for key in [0...@length]
      value for key, value of output

Array::where = (query) ->
    return [] if typeof query isnt "object"
    hit = Object.keys(query).length
    @filter (item) ->
        match = 0
        for key, val of query
            match += 1 if item[key] is val
        if match is hit then true else false

DataStore = require './data-store'

passport = require 'passport'
BearerStrategy = require 'passport-http-bearer'
AnonymousStrategy = require 'passport-anonymous'

passport.use new AnonymousStrategy

authorizer = (store) ->
    if store.authorizer? and store.authorizer instanceof DataStore
        passport.use new BearerStrategy (token,done) ->
            token = store.authorizer.findRecord 'token', token
            identity = token.get('identity') if token instanceof DataStore.Model

            unless identity? and identity instanceof DataStore.Model
                done null, false
            else
                done null, identity, { scope: identity.get('scope') }
        passport.authenticate('bearer', {session:false})
    else
        passport.authenticate('anonymous', {session:false})

serializer = (data) ->
    switch
        when data instanceof Array
            (serializer(entry) for entry in data)
        when data instanceof DataStore.Model
            data.serialize true
        else
            data

poster = (store,type) -> () ->
    try
        assert store instanceof DataStore and type? and store.entities[type]? and @body[type]?, "invalid POST request!"
    catch err
        return @res.send 500, error:err

    requestor = @req.user
    return @next() unless requestor?

    try
        record = store.createRecord type, @body[type]
    catch err
        return @res.send 500, error: err

    record.save (err, props) =>
        return @res.send 500, error: err if err?
        if props?
            @req.result = record.serialize true
            @next()
        else
            @res.send 404

getter = (store,type) -> () ->
    requestor = @req.user
    condition = @query.ids
    condition ?= @params.id

    return @res.send 400 unless requestor? and type?
    return @res.send 403 if condition isnt undefined and 'all' not in @req.authInfo?.scope

    store.find type, condition, (err, matches) =>
        return @res.send 500, error: err if err?
        if matches? and matches.length > 0
            o = {}
            o[type] = serializer(matches)
            @req.result = o
            store.auditor?.info query:condition, result:@req.result, 'getter results for %s',type
            @next()
        else
            @res.send 404

putter = (store,type) -> () ->
    requestor = @req.user
    return @next() unless requestor? and type?

    store.updateRecord type, @params.id, @body, (err,result) =>
        return @res.send 500, error: err if err?
        if result?
            @req.result = result
            log.debug query:@params.id,result:@req.result, 'putter results for %s',type
            @next()
        else
            @res.send 404

remover = (store,type) -> () ->
    requestor = @req.user
    return @next() unless requestor? and type?

    store.deleteRecord type, @params.id, (err,result) =>
        return @res.send 500, error: err if err?
        if result?
            @req.result = result
            log.debug query:@params.id,result:@req.result, 'remover results for %s',type
            @next()
        else
            @res.send 404

#
# EXPORTS
#
module.exports =
    DS: DataStore
    authorizer: authorizer
    poster: poster
    getter: getter
    putter: putter
    remover: remover

# must be called in the context of a given web server
module.exports.serve = (store,opts) ->
    assert this.post? and this.get? and this.put? and this.del?, "cannot stormify.serve without CRUD operators present in the running context!"
    assert store instanceof DataStore, "cannot stormify.serve without valid instance of DataStore!"

    store.log?.info method:"serve", "STORMIFYING data entities!"

    baseUrl = opts?.baseUrl or ''
    for name, entity of store.entities
        store.log?.debug method:"serve", "processing #{name}..."
        continue if entity.hidden

        if entity.serve?
            entity.serve.call @, opts
            store.log?.info method:"serve", "serving custom REST endpoint(s) for: #{name}"
            continue if entity.serveOverride

        collection = entity.collection
        @post "#{baseUrl}/#{collection}",     authorizer(store), poster(store,name), -> @send @req.result
        @get  "#{baseUrl}/#{collection}",     authorizer(store), getter(store,name), -> @send @req.result
        @get  "#{baseUrl}/#{collection}/:id", authorizer(store), getter(store,name), -> @send @req.result
        @put  "#{baseUrl}/#{collection}/:id", authorizer(store), putter(store,name), -> @send @req.result
        @del  "#{baseUrl}/#{collection}/:id", authorizer(store),remover(store,name), -> @send 204

        store.log?.info method:"serve", "auto-generated REST endpoints at: #{baseUrl}/#{name}"

    # open up a socket.io connection stream for store updates
