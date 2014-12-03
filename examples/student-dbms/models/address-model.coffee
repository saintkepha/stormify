stormify = require '../../../src/stormify'
DS = stormify.DS

class AddressModel extends DS.Model
    name: 'address'
    schema:   
        id:        DS.attr 'string', required: false
        doorno:		DS.attr 'string', required: true  
        street:    DS.attr 'string', required: true        
        place:    DS.attr 'string', required: true   
        city:		DS.attr 'string', required: true           
        zipcode:  	DS.attr 'number', required: false  
        phoneno:  	DS.attr 'number', required: false     
module.exports = AddressModel
