stormify = require '../../../src/stormify'
util = require 'util'
DS = stormify.DS

class StudentController extends DS.Controller

    beforeDestroy: ->
        #before remove it from the student DB, lets delete the marks db entry and address db entry
        util.log "model id is " + @model.id
   
        #get the student record, and delete the respective address /marks records 
        record = @store.findRecord 'student',@model.id
        
        address = record.properties.address.value
        #delete the address record from address.db
        @store.deleteRecord 'address', address.id


        marks = record.properties.marks.value
        #delete the mark records from mark.db
        for mark in marks            
            @store.deleteRecord 'mark', mark.id

        #now delete the record from student.db
        super
    
    beforeUpdate: ->
        util.log "updating the student entry- PUT call"
        #to be implemented
        super

    beforeSave: ->
        #validation
        #read the courseid from the input data   
        courseid = @model.get 'courseid'
        util.log 'courseid ' + courseid
        
        #get the course record matching with courseid
        record = @store.findRecord 'course',courseid
        util.log 'course table - record.propeties.id.value' + record.properties.id.value
        return unless courseid is record.properties.id.value  # course id is not existing in the  table               

        #address processing
        #read the address from the input data        
        addressdata = @model.get 'address'   
        util.log "address is " + util.inspect addressdata
        unless addressdata instanceof DS.Model           
            addressrecord = @store.createRecord 'address', addressdata
            util.log "address record id is " + util.inspect addressrecord.id
            #assign the uuid of the address to the student db 
            addressdata.id = addressrecord.id
            addressrecord.save =>
                #saves the record in address db
                @model.save()

            
        #marks - processing 
        marks = @model.get 'marks'   
        util.log "marks are " + util.inspect marks
        for mark in marks
            unless mark instanceof DS.Model           
                markrecord = @store.createRecord 'mark', mark
                #util.log "markrecord is " + util.inspect markrecord.id
                mark.id = markrecord.id
                markrecord.save =>
                    #saves the record in mark db
                    @model.save()
               
        #now save the student record
        super             




module.exports = StudentController

