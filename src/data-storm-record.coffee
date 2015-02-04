DataStormModel = require './data-storm-model'

#----
# A model for representing an Active Record instance of a given DataStormModel

class DataStormRecord extends DataStormModel

    @Promise = require 'promise'

    async = require 'async'

    constructor: (model, data, @parent) ->
        assert model instanceof DataStormModel,
            "Cannot create an instance of DataStormRecord without a valid DataStormModel"

        assert @parent instanceof DataStormRecord,
            "Cannot create an instance of DataStormRecord without a parent DataStormRecord"

        super model._schema # absorb the passed-in model into the record model

        @name = model.constructor.name

        @_isSaving = @_isSaved = @_isDestroy = @_isDestroyed = false
        @_records = {} # hash map of sub-records

        return @ unless data?

        @setProperties data
        @id = @get('id')


        @parent.log.debug "done constructing #{@name}"
        assert violations.length == 0, violations

    # update: (data) ->
    #     assert @_isDestroyed is false, "attempting to update a destroyed record"

    #     # if controller associated, issue the updateRecord action call
    #     @controller?.beforeUpdate? data
    #     @setProperties data
    #     @controller?.afterUpdate? data

    removeReferences: (record,isSaveAfter) ->
        return unless record instanceof DataStormRecord
        changes = 0
        for key, relation of @_relations
            continue unless relation.modelName is record.name
            @parent.log.debug method:'removeReferences',id:@id,"clearing #{key}.#{relation.type} '#{relation.model}' containing #{record.id}..."
            try
                switch relation.kind
                    when 'belongsTo' then @set key, null if @get(key)?.id is record.id
                    when 'hasMany'   then @set key, @get(key).without id:record.id
            catch err
                @parent.log.debug method:'removeReferences', error:err, "issue encountered while attempting to clear #{@name}.#{key} where #{relation.model}=#{record.id}"

        @save() if @_isSaved is true and isSaveAfter is true and @isDirty()

    save: (callback) ->
        assert @_isDestroyed is false, "attempting to save a destroyed record"

        if @_isSaving is true
            return callback? null, this

        @_isSaving = true
        try
            @validate()
        catch err
            @parent.log.error method:'save',record:@name,id:@id,error:err,'failed to satisfy beforeSave controller hook'
            @_isSaving = false
            callback? err
            throw err

        # getting properties performs validations on this model
        @getProperties (err,props) =>
            if err?
                @parent.log.error method:'save',id:@id,error:err, 'failed to retrieve validated properties before committing to store'
                return callback err

            @parent.log.debug method:'save',record:@name,id:@id, "saving record"
            try
                @parent.commit this
                @clearDirty()
            catch err
                @parent.log.warn method:'save',record:@name,id:@id,error:err,'issue during commit record to the store, ignoring...'

            try
                @controller?.afterSave?()
                @_isSaved = true

                callback? null, this, props
            catch err
                @parent.log.error method:'save',record:@name,id:@id,error:err,'failed to commit record to the store!'

                # we self-destruct only if this record wasn't saved previously
                @destroy() unless @_isSaved is true

                callback? err
                throw err

            finally
                @_isSaving = false

    # a method to invoke a registered promised action on the record
    invoke: (action, params, data) ->
        new @Promise (resolve,reject) =>
            try
                resolve @_actions[action]?.call(this, params, data)
            catch err
                reject err

    destroy: (callback) ->
        # if controller associated, issue the destroy action call
        @_isDestroy = true
        try
            @controller?.beforeDestroy?()
            @parent.commit this
            @_isDestroyed = true
            @controller?.afterDestroy?()
        catch err
            @parent.log.warn method:'destroy',record:@name,id:@id,error:err,'encountered issues during destroy, ignoring...'
        finally
            callback? null, true

    # customize how data gets saved into DataStoreRegistry
    # this operation cannot be async, it means it will extract only known current values.
    # but it doesn't matter since computed data will be re-computed once instantiated
    serialize: (opts) ->
        assert @_isDestroyed is false, "attempting to serialize a destroyed record"

        result = id: @id
        for prop,data of @_properties when data.value?
            x = data.value
            result[prop] = switch
                when x instanceof DataStormRecord
                    if opts?.embedded is true
                        json = x.serialize()
                        delete json.id # we strip ID from response since it is irrelevant
                        json
                    else
                        x.id
                when x instanceof Array
                    (if y instanceof DataStormRecord then y.id else y) for y in x
                else x

        return result unless opts?.tag is true

        data = {}
        data["#{@name}"] = result
        data




module.exports = DataStormRecord
