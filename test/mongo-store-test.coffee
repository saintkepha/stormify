DS = require('mdata-store')
MongoRegistry = require('stormregistry').MongoRegistry
assert = require 'assert'
Mongo = require('mongoskin');
should = require('chai').should()
expect = require('chai').expect
assert = require('chai').assert
helper = Mongo.helper


class TestModel extends DS.Model

    name: 'test'

    schema:
        hwIdentifier: DS.attr 'string', required:true
        hwModel:      DS.attr 'string', required:true
        type:         DS.attr 'string', required:true, validator: (value) ->
            switch value
                when 'Desktop','Tablet','Mobile' then value
                else 'Desktop' # default to Desktop for now
        osName:       DS.attr 'string', required:true
        osVersion:    DS.attr 'string', required:true
        locale:       DS.attr 'string'
        isBlocked:    DS.attr 'boolean', defaultValue: false
        timeSpent:    DS.attr 'number', defaultValue: 0
        loginOn:      DS.attr 'date'
        lastLoginOn:  DS.attr 'date'
        blockedOn:    DS.attr 'date'

        activatedOn:  DS.computed (-> @get 'createdOn'), property: 'createdOn'
        vendor: DS.computed (->
            switch @get 'osName'
                when 'iOS', 'MAC' then 'apple'
                when 'ANDROID', 'Android' then 'google'
                when 'WINDOWS', 'Windows' then 'microsoft'
                else 'unknown'
        ), property: 'osName'

class TestDataStore extends DS
    constructor: (opts) ->
        super opts
        store = this
        @contains 'test',
            model:TestModel
        @initialize()
describe 'MongoStore', () ->
    db = null
    mongo = null
    store = null
    before (done) ->
        db = Mongo.db("mongodb://localhost:27017/intg_tests", {native_parser:true,safe:true})
        db.open (err)->
            should.not.exist(err)
            mongo = new MongoRegistry(db:db, collection:'test')
            store = new TestDataStore(name:'test',db:db,collection:'test')
            done()

    describe '#createRecord()', ()->
        it 'should create the record in a store', (done) ->

            done()
    describe '#findRecord()', ()->
        it 'should find the record from the store', (done) ->

            done()
