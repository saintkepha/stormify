assert = require 'assert'

Array::unique = ->
      output = {}
      for key in [0..@length-1]
        val = @[key]
        switch
            when typeof val is 'object' and val.id?
                output[val.id] = val
            else
                output[val] = val
      #output[@[key]] = @[key] for key in [0...@length]
      value for key, value of output

Array::contains = (query) ->
    return false if typeof query isnt "object"
    hit = Object.keys(query).length
    @some (item) ->
        match = 0
        for key, val of query
            match += 1 if item[key] is val
        if match is hit then true else false

Array::where = (query) ->
    return [] if typeof query isnt "object"
    hit = Object.keys(query).length
    @filter (item) ->
        match = 0
        for key, val of query
            match += 1 if item[key] is val
        if match is hit then true else false

Array::without = (query) ->
    return @ if typeof query isnt "object"
    @filter (item) ->
        for key,val of query
            return true unless item[key] is val
        false # item matched all query params

Array::pushRecord = (record) ->
    return null if typeof record isnt "object"
    @push record unless @contains(id:record.id)

DataStore = require './data-store'

createStore = (opts) ->
    assert opts.store?.prototype?.constructor?.name, "store must be a class definition for the DataStore"

    store = new opts.store
        auditor: opts.auditor
        authorizer: opts.authorizer
        datadir:opts.datadir

    assert store instanceof DataStore, "unable to instantiate store as DataStore instance"
    store

passport = require 'passport'
BearerStrategy = require 'passport-http-bearer'
AnonymousStrategy = require 'passport-anonymous'

passport.use new AnonymousStrategy

authorizer = (store) ->
    if store.authorizer? and store.authorizer instanceof DataStore
        passport.use new BearerStrategy (token,done) ->
            token = store.authorizer.findRecord 'token', token
            # should verify that it is AuthorizationToken once we bundle that in stormify
            if token? and token instanceof DataStore.Model
                identity = token.get('identity')
                session = token.get('session')
                if identity? and session?
                    return done null, session, { scope: identity.get('scope') }

            # default case is unauthorized...
            done null, false

        passport.authenticate('bearer', {session:false})
    else
        passport.authenticate('anonymous', {session:false})

serializer = (data) ->
    switch
        when data instanceof Array
            (serializer(entry) for entry in data)
        when data instanceof DataStore.Model
            data.serialize()
        else
            data

poster = (store,type) -> (req,res,next) ->
    assert store instanceof DataStore and type? and store.entities.hasOwnProperty(type), "invalid stormify.poster initialization"
    try
        assert req.body? and req.body.hasOwnProperty(type), "attempting to POST without proper '#{type}' as root element!"
    catch err
        return res.status(500).send error:err

    store.log?.info stormify:"poster",request:req.body,"stormify.poster for '#{type}'"
    try
        record = store.open(req.user).createRecord type, req.body[type]
        record.save (err, props) =>
            unless err?
                res.locals.result = record.serialize tag:true
                store.log?.info query:req.params.id,result:res.locals.result, 'poster results for %s',type
                next()
            else
                res.status(500).send error:
                    message: "Unable to create a new record for #{type} during save"
                    origin: err

    catch err
        unless res.headersSent
            res.status(500).send error:
                message: "Unable to create a new record for #{type}"
                origin: err
            throw err


getter = (store,type) -> (req,res,next) ->
    assert store instanceof DataStore and type? and store.entities.hasOwnProperty(type), "invalid stormify.getter initialization"

    condition = req.query.ids  # see if array of IDs
    condition ?= req.params.id # see if a specific ID
    condition ?= req.query if Object.keys(req.query).length isnt 0 # otherwise likely an object with key/val conditions

    collection = store.entities[type].collection
    store.log?.info stormify:"getter",query:condition,"stormify.getter for '#{type}'"

    # allow condition to be an object
    try
        store.open(req.user).find type, condition, (err, matches) =>
            throw err if err?

            # we looked for one but got questionable results
            if req.params.id? and matches.length isnt 1
                return res.status(404).send()

            res.locals.matches = matches
            o = {}
            res.locals.result = switch
                when (condition instanceof Array) or (condition instanceof Object) or not condition?
                    o[collection] = serializer(matches)
                    o
                else
                    o[type] = serializer(matches[0])
                    o
            store.log?.info query:condition, matches:matches.length, "getter for '%s' was successful",type
            store.log?.debug query:condition, result:res.locals.result, 'getter results for %s',type

            # do NOT cache this response from getter!
            res.setHeader 'Expires','-1'
            next()
    catch err
        return res.status(500).send error:
            message: "Unable to perform find operation for #{type}"
            origin: err


putter = (store,type) -> (req,res,next) ->
    assert store instanceof DataStore and type? and store.entities.hasOwnProperty(type), "invalid stormify.poster initialization"
    try
        assert req.body? and req.body.hasOwnProperty(type), "attempting to PUT without proper '#{type}' as root element!"
    catch err
        return res.status(500).send error:err

    store.log?.info stormify:"putter",request:req.body,"stormify.putter for '#{type}'"

    try
        store.open(req.user).updateRecord type, req.params.id, req.body[type], (err,result) =>
            throw err if err?

            if result? and result instanceof DataStore.Model
                res.locals.result = result.serialize tag:true
                store.log?.info query:req.params.id,result:res.locals.result, 'putter results for %s',type
                next()
            else
                res.status(404).send()
    catch err
        return res.status(500).send error:
            message: "Unable to perform update operation for #{type}"
            origin: err

remover = (store,type) -> (req,res,next) ->
    assert store instanceof DataStore and type? and store.entities.hasOwnProperty(type), "invalid stormify.remover initialization"

    store.log?.info stormify:"remover","stormify.remover for '#{type}'"

    try
        store.open(req.user).deleteRecord type, req.params.id, (err,result) =>
            unless err? and result is false
                res.locals.result = result
                store.log?.debug query:req.params.id,result:res.locals.result, 'remover results for %s',type
                next()
            else
                res.status(400).send()
    catch err
        return res.status(500).send error:
            message: "Unable to perform delete operation for #{type}"
            origin: err

#
# EXPORTS
#
module.exports =
    createStore: createStore
    SR: require './stormregistry'
    DS: DataStore
    authorizer: authorizer
    poster: poster
    getter: getter
    putter: putter
    remover: remover

# must be called in the context of a given web server
module.exports.serve = (store,opts) ->
    @del ?= @delete
    assert this.post? and this.get? and this.put? and this.del?, "cannot stormify.serve without CRUD operators present in the running context!"
    assert store instanceof DataStore, "cannot stormify.serve without valid instance of DataStore!"

    store.log?.info method:"serve", "STORMIFYING data entities!"

    baseUrl = opts?.baseUrl or ''
    for collection, entity of store.collections
        store.log?.debug method:"serve", "processing #{collection}..."
        continue if entity.hidden

        if entity.serve?
            entity.serve.call @, opts
            store.log?.info method:"serve",
                "serving custom REST endpoint(s) for: #{collection}"
            continue if entity.serveOverride

        name = entity.name
        @get  "#{baseUrl}/#{collection}",     authorizer(store), getter(store,name), -> @send @res.locals.result
        @get  "#{baseUrl}/#{collection}/:id", authorizer(store), getter(store,name), -> @send @res.locals.result

        unless entity.isReadOnly or entity.persist is false
            @post "#{baseUrl}/#{collection}",     authorizer(store), poster(store,name), -> @send @res.locals.result
            @put  "#{baseUrl}/#{collection}/:id", authorizer(store), putter(store,name), -> @send @res.locals.result
            @del  "#{baseUrl}/#{collection}/:id", authorizer(store),remover(store,name), -> @res.status(204).send()

            # attach controller actions to the REST endpoint
            for action of entity.controller?::actions
                do (action) =>
                    store.log?.info method: "serve",
                        "exposing actions: #{baseUrl}/#{collection}/:id/#{action}"
                    @post "#{baseUrl}/#{collection}/:id/#{action}", authorizer(store), getter(store,name), ->
                        record = @res.locals.matches[0] # only assume ONE
                        record.invoke action, @req.query, @req.body
                        .then(
                            (response) => @send response
                            (error) => @res.status(500).send error: error
                        )

        store.log?.info method:"serve",
            "auto-generated REST endpoints at: #{baseUrl}/#{collection}"

    # open up a socket.io connection stream for store updates
