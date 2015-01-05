stormify = require '../../lib/stormify'

class TestDataStore extends stormify.DS

    name: "test-ds"
    constructor: (opts) ->
        super opts
        store = this        
        @contains 'address',
            model: require '../models/test-model'
            #controller: require '../controllers/test-controller'

        @initialize()                        

module.exports = TestDataStore