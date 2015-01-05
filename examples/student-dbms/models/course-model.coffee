stormify = require '../../../src/stormify'
DS = stormify.DS

class CourseModel extends DS.Model

    name: 'course'
    schema:   
        id:            DS.attr 'string', required: false
        name:          DS.attr 'string', required: true        
        department:    DS.attr 'string', required: true   
module.exports = CourseModel
