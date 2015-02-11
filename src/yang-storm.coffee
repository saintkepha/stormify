DS = require './data-storm'

# Promise = require 'bluebird'
# Promise.promisifyAll needle

class YangStorm extends DS

  @Generator = require './yang/yang-generator'

  constructor: ->
    @generator = new YangStorm.Generator
    super

  needle = require 'needle'
  import: (yang) ->
    @assert yang? and typeof yang is 'string',
      'cannot import without valid YANG text input'

    if /\b((?=[a-z0-9-]{1,63}\.)(xn--)?[a-z0-9]+(-[a-z0-9]+)*\.)+[a-z]{2,63}\b/.test(yang)
      needle.get yang, (err, res) ->
        try
          module = @generator.generate res.body
        catch err
          console.log err
        module

module.exports = YangStorm
