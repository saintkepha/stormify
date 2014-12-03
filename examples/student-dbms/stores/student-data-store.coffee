stormify = require '../../../src/stormify'

class StudentDataStore extends stormify.DS

    name: "student-ds"
    constructor: (opts) ->

        super opts
        store = this
        @contains 'addresses',
            model: require '../models/address-model'           

        @contains 'courses',
            model: require '../models/course-model'            

        @contains 'students',
            model: require '../models/student-model'
            controller: require '../controllers/student-controller'

        @contains 'marks',
            model: require '../models/mark-model'            

        @initialize()                        

module.exports = StudentDataStore