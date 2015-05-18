MongoRegistry = require('../src/stormregistry').MongoRegistry
assert = require 'assert'
Mongo = require('mongoskin');
should = require('chai').should()
expect = require('chai').expect
assert = require('chai').assert
helper = Mongo.helper

describe 'MongoRegistry', ()->
    db = null
    mongo = null
    before (done) ->
        db = Mongo.db("mongodb://localhost:27017/intg_tests", {native_parser:true,safe:true})
        db.open (err)->
            should.not.exist(err)
            done()
            mongo = new MongoRegistry(db:db, collection:'Test')

    describe '#add()', ()->
        it 'should add the record successfully', (done) ->
            mongo.add {id:'some id'}, {id:'some id',name:'Test',descp:'Test Description'}
            .then (result)->
                expect(result.id).to.equal('some id')
                done()
            ,(error) ->
                console.log 'Record not added' + error
                done()

    describe '#update()', ()->
        it 'should update the record successfully', (done) ->
            mongo.update {name:"Test"}, {name:'Test2',descp:'Test update Description'}
            .then (result) ->
                expect(result).to.equal(1)
                done()
            , (error) ->
                console.log 'Record not updated' + error
                done()

    describe "#get()", ()->
        it 'should fetch the first found record', (done) ->
            mongo.get {name:'Test2'}
            .then (result) ->
                expect(result.name).to.equal('Test2')
                done()
            , (err) ->
                console.log 'Not Found record'
                done()

    describe "#find()", ()->
        it 'should fetch the records found', (done) ->
            mongo.find {_id: helper.toObjectID('555a60931af4146454ba6f92')}
            .then (result) ->
                result.each (err,record) ->
                    if err? or not record
                        return
                    console.log 'Found record ' + JSON.stringify record
                result.should.be.a('object')
                done()
            , (err) ->
                console.log 'Not Found record'
                done()

    describe "#list()", ()->
        it 'should fetch all the available records found', (done) ->
            mongo.list()
            .then (result) ->
                count = 0
                result.each (err,record) ->
                    if err? or not record
                        assert.isAbove(count,0,'Record count must be greater than 1.')
                        done()
                        return
                    count = count + 1

            , (err) ->
                console.log 'No records found'
                done()

    describe "#remove()", ()->
        it 'should remove the record by given ID', (done) ->
            mongo.remove {name:'Test2'}
            .then (result) ->
                expect(result).to.equal(1)
                done()
            , (err) ->
                console.log 'Not found ' + err
                done()
