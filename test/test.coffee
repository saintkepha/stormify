stormify = require '../lib/stormify'
DS = stormify.DS
assert = require('chai').assert
should = require('chai').should
expect = require('chai').expect
sinon = require('sinon')


SDS = stormify.createStore
	store: require './stores/test-store'
	#auditor: log.child store: 'test-ds'

data =
	id : 501
	street : "O.M.R"
	city : "chennai"
	phoneno : 100

describe 'DS.Model unit test cases ', -> 
	it 'Basic DSModel object creation test', ->

		#Test the createRecord function
		TestModel = SDS.createRecord 'address', data
		assert.isDefined(TestModel)
		#TestModel.save()	
		#verify the created model data with the input data
		expect(TestModel.id).to.equal(data.id)
		expect(TestModel.properties.id.value).to.equal(data.id)
		expect(TestModel.properties.street.value).to.equal(data.street)
		expect(TestModel.properties.city.value).to.equal(data.city)
		expect(TestModel.properties.phoneno.value).to.equal(data.phoneno)

		#Test the findRecord function
		TestModel = null
		TestModel = SDS.findRecord 'address', data.id
		assert.isDefined(TestModel)
		#console.log TestModel
		expect(TestModel.id).to.equal(data.id)
		expect(TestModel.properties.id.value).to.equal(data.id)
		expect(TestModel.properties.street.value).to.equal(data.street)
		expect(TestModel.properties.city.value).to.equal(data.city)
		expect(TestModel.properties.phoneno.value).to.equal(data.phoneno)

		#Test the findBy function
		TestModel = null
		result = SDS.findBy 'address', city:"chennai"
		#result is array 
		assert.isDefined result
		for res in result
			assert.isDefined res
			

		console.log result




