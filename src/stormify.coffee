assert = require 'assert'

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

##
# Create an instance of stormify express app to be used by the
# invoking routine to mount as a sub-app or to run as the primary app
#
# USAGE:
#
# stormify = require 'stormify'
#
# 1. use a new editable blank DataStorm instance
#
# storm = stormify.express new stormify.DS name:'blank', edit:true
#
# 1a. mount as a sub-app middleware to existing express
#
# @use storm
# or
# @use '/someplace', storm
#
# 1b. run as the primary express app
#
# storm.listen 5330
#
# 2. use a pre-defined DataStorm instance
#
# class StuffStorm extends stormify.DS
#   name: 'newstorm'
#   schema:
#     stuff: @hasMany stormify.DS.Model
#
# @use stormify.express new StuffStorm
#
module.exports.express = (ds) ->
    assert ds instanceof DataStorm,
        'cannot express without valid DataStorm passed-in'

    app = (require 'express')()
    bp = require 'body-parser'

    app.use bp.urlencoded(extended:true), bp.json(strict:true), (require 'passport').initialize()

    ds.once 'ready', ->
        app.use

    serializer = (data) ->
        switch
            when data instanceof Array
                (serializer(entry) for entry in data)
            when data instanceof DataStorm.Model
                data.serialize()
            else
                data

    router = (require 'express').Router()
    router.param 'collection', (req,res,next,collection) ->
        req.collection = req.storm.contains collection
        if req.collection? then next() else next('route')

    router.param 'id', (req,res,next,id) ->
        assert req.collection?,
            "cannot retrieve '#{id}' without a valid collection!"
        req.record = req.collection.find id
        if req.record? then next() else next('route')

    router.param 'action', (req,res,next,action) ->
        assert req.record?,
            "cannot perform '#{action}' without a record to operate on!"
        req.action = req.record.invoke action, req.query, req.body # returns a Promise
        if req.action? then next() else next('route')

    router.all '*', (authorizer ds), (req,res,next) ->
        req.storm = ds.open req.user
        next()

    ##
    # provide handling of this DataStorm
    ##
    router.route "/"
    .all (req, res, next) ->
        # XXX - verify req.user has permissions to operate on the DataStorm
        #
        next()
    .get (req, res, next) ->
        res.locals.result = req.storm.serialize()
        next()
    .post (req, res, next) ->
        # XXX - Enable creation of a new collection into the target DataStorm
        next()
    .copy (req, res, next) ->
        # XXX - generate JSON serialized copy of this DataStorm
        next()

    ##
    # provide handling of this DataStorm's Collection
    ##
    router.route "#{ds.name}/:collection"
    .all (req, res, next) ->
        # XXX - verify req.user has permissions to operate on the DataStorm.Collection
        #
        next()
    .get (req, res, next) ->
        res.locals.result = req.collection.serialize()
        next()
    .put (req, res, next) ->
        assert req.body? and req.body.hasOwnProperty req.collection.name,
            "attempting to PUT without proper '#{req.collection.name}' as root element"
        req.collection.update req.body[req.collection.name]
        req.collection.save (err, result) ->
            if err then return next err
            res.locals.result = @serialize()
            next()
    .copy (req, res, next) ->
        # return full copy of the entire collection records
        res.locals.result = req.collection.registry.list()
        next()
    .merge (req, res, next) ->
        # import passed-in records into current collection records
        assert req.body? and req.body.hasOwnProperty req.collection.modelName,
            "attempting to MERGE without proper '#{req.collection.modelName} as root element"
        req.collection.registry.merge req.body[req.collection.modelName]
        next()
    .subscribe (req, res, next) ->
        checksum = req.body # XXX - calculate checksum
        unless req.collection.subscribers.hasOwnProperty checksum
            # remember the callback with checksum of req.body so that we can unsubscribe the notify request
            req.collection.subscribers[checksum] =
                event: req.body.event
                callback: callback = (record) ->
                    request
                        url: req.body.url
                        method: 'notify'
                        body: id: checksum, data: record.serialize()
            req.collection.on req.body.event, callback

        res.locals.result = id: checksum
        next()
    .unsubscribe (req, res, next) ->
        subscription = req.collection.subscribers[req.body.id]
        if subscription?
            req.collection.removeListener subscription.event, subscription.callback
        next()

    ##
    # provide handling of top-level collection endpoint
    ##
    router.route ':collection'
    .all (req, res, next) ->
        # XXX - verify req.user has permissions to operate at the top-level collection
        #
        next()
    .get (req, res, next) ->
        condition = req.query.ids  # see if array of IDs
        condition ?= req.query if Object.keys(req.query).length isnt 0 # otherwise likely an object with key/val conditions
        req.collection.find condition, (err, matches) ->
            if err then return next err
            res.locals.result = serializer matches
            next()
    .post (req, res, next) ->
        assert req.body? and req.body.hasOwnProperty req.collection.modelName,
            "attempting to POST without proper '#{req.collection.modelName}' as root element!"
        payload = req.body[req.collection.modelName]
        if payload instanceof Array
            return next new Error "bulk POST not yet implemented!"
        record = req.storm.createRecord req.collection.modelName, payload
        record.save (err, result) ->
            if err then return next err
            res.locals.result = @serialize()
            next()
    .head (req, res, next) ->
        # XXX - calculate checksum of this collection
        res.locals.result = 'some-checksum'
        next()

    ##
    # provide handling of explicit collection record entry
    ##
    router.route ':collection/:id'
    .all (req, res, next) -> next()
    .get (req, res, next) ->
        res.locals.result = req.record.serialize()
        next()
    .put (req, res, next) ->
        assert req.body? and req.body.hasOwnProperty req.record.name,
            "attempting to PUT without proper '#{req.record.name}' as root element!"
        req.record.update req.body[req.record.name]
        req.record.save (err, result) ->
            if err then return next err
            res.locals.result = @serialize()
            next()
    .delete (req, res, next) ->
        req.record.destroy (err, result) ->
            if err then return next err
            res.locals.result = result
            next()

    ##
    # provide handling of controller actions on a matching record
    ##
    router.route ":collection/:id/:action"
    .post (req, res, next) ->
        req.action.then (
            (response) ->
                res.locals.result = response
                next()
            (error) -> next error
        )

    # always send back contents of 'result' if available
    router.use (req, res, next) ->
        unless res.locals.result? then return next 'route'
        res.setHeader 'Expires','-1'
        o = {}
        o[req.collection.modelName] = res.locals.result
        res.send o
        next()

    # default log successful transaction
    router.use (req, res, next) ->
        req.storm.log?.info query:req.params.id,result:res.locals.result, 'PUT results for %s', req.record.name
        next()

    # default 'catch-all' error handler
    router.use (err, req, res, next) ->
        res.status(500).send error: err

    # open up a socket.io connection stream for store updates

    return app

#----------------------
# OLD DEPRECATED METHOD
#----------------------
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


