stormify = require '../../../src/stormify'

DS = stormify.DS

class StudentModel extends DS.Model

    name: 'student'
    schema:
        name:       DS.attr 'string', required: true                
        address:	DS.belongsTo 'address', required: true                  
        courseid:	DS.attr 'string', required: true  # key for major table        
        marks:		DS.hasMany 'mark', required: true
        result:     DS.computed (-> 
            for mark in @get 'marks'
                return 'fail' if mark.mark < 50
            'pass'
            ), property: 'marks'  
module.exports = StudentModel
