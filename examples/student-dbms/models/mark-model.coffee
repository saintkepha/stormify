stormify = require '../../../src/stormify'
DS = stormify.DS

class MarkModel extends DS.Model
    name: 'mark'
    schema:   
        id:        	DS.attr 'string', required: false
        subject:	DS.attr 'string', required: true  
        mark:    	DS.attr 'number', required: true          
        
module.exports = MarkModel
