// Generated by CoffeeScript 1.8.0
(function() {
  var TestDataStore, stormify,
    __hasProp = {}.hasOwnProperty,
    __extends = function(child, parent) { for (var key in parent) { if (__hasProp.call(parent, key)) child[key] = parent[key]; } function ctor() { this.constructor = child; } ctor.prototype = parent.prototype; child.prototype = new ctor(); child.__super__ = parent.prototype; return child; };

  stormify = require('../../lib/stormify');

  TestDataStore = (function(_super) {
    __extends(TestDataStore, _super);

    TestDataStore.prototype.name = "test-ds";

    function TestDataStore(opts) {
      var store;
      TestDataStore.__super__.constructor.call(this, opts);
      store = this;
      this.contains('address', {
        model: require('../models/test-model')
      });
      this.initialize();
    }

    return TestDataStore;

  })(stormify.DS);

  module.exports = TestDataStore;

}).call(this);