stormify = require '../../lib/stormify'
DS = stormify.DS

class TestModel extends DS.Model
    name: 'address'
    schema:   
        id:        DS.attr 'string', required: false        
        street:    DS.attr 'string', required: true                 
        city:		DS.attr 'string', required: true                   
        phoneno:  	DS.attr 'number', required: true
        date :		DS.attr 'date', required: false

module.exports = TestModel
