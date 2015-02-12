// Generated by CoffeeScript 1.8.0
(function() {
  var StormClass, StormObject, Yang, YangContainer, YangExtension, YangGrouping, YangList, YangListEntry, YangModule, YangObject, YangProperty, YangRemoteProcedure,
    __hasProp = {}.hasOwnProperty,
    __extends = function(child, parent) { for (var key in parent) { if (__hasProp.call(parent, key)) child[key] = parent[key]; } function ctor() { this.constructor = child; } ctor.prototype = parent.prototype; child.prototype = new ctor(); child.__super__ = parent.prototype; return child; };

  StormClass = require('../storm/storm-class');

  StormObject = require('../storm/storm-object');

  YangModule = require('./yang-module');

  YangObject = (function(_super) {
    __extends(YangObject, _super);

    function YangObject() {
      return YangObject.__super__.constructor.apply(this, arguments);
    }

    return YangObject;

  })(StormObject);


  /**
   * `YangGrouping` is purely a logical schema abstraction to allow
   * "tagging" of sections of schema for reference use by other YANG
   * schemas.
   *
   * So although we do create a `StormObject` mapping within the class
   * hierarchy of the overall `YangModel`, it should not be directly
   * referenced as property setter/getter.
   */

  YangGrouping = (function(_super) {
    __extends(YangGrouping, _super);

    function YangGrouping() {
      return YangGrouping.__super__.constructor.apply(this, arguments);
    }

    return YangGrouping;

  })(YangObject);

  YangContainer = (function(_super) {
    __extends(YangContainer, _super);

    function YangContainer() {
      return YangContainer.__super__.constructor.apply(this, arguments);
    }

    return YangContainer;

  })(YangObject);

  YangExtension = (function(_super) {
    __extends(YangExtension, _super);

    function YangExtension() {
      return YangExtension.__super__.constructor.apply(this, arguments);
    }

    return YangExtension;

  })(YangObject);

  YangListEntry = (function(_super) {
    __extends(YangListEntry, _super);

    function YangListEntry() {
      return YangListEntry.__super__.constructor.apply(this, arguments);
    }

    return YangListEntry;

  })(YangObject);

  YangProperty = (function(_super) {
    __extends(YangProperty, _super);

    function YangProperty() {
      return YangProperty.__super__.constructor.apply(this, arguments);
    }

    return YangProperty;

  })(YangObject.Property);

  YangList = (function(_super) {
    __extends(YangList, _super);

    YangList.Entry = YangListEntry;

    function YangList(model, opts, obj) {
      this.model = model;
      YangList.__super__.constructor.call(this, 'array', opts, obj);
    }

    return YangList;

  })(YangProperty);

  YangRemoteProcedure = (function(_super) {
    __extends(YangRemoteProcedure, _super);

    function YangRemoteProcedure() {
      return YangRemoteProcedure.__super__.constructor.apply(this, arguments);
    }

    return YangRemoteProcedure;

  })(YangObject);

  Yang = (function(_super) {
    __extends(Yang, _super);

    function Yang() {
      return Yang.__super__.constructor.apply(this, arguments);
    }

    Yang.set({
      module: YangModule,
      grouping: YangGrouping,
      container: YangContainer,
      list: YangList,
      extension: YangExtension,
      leaf: YangProperty,
      'leaf-list': YangProperty,
      rpc: YangRemoteProcedure
    });

    Yang.define = function(keyword, args) {
      var Override, functions, k, name, statics, v, _ref;
      _ref = keyword.split(' '), keyword = _ref[0], name = _ref[1];
      statics = {};
      functions = {};
      for (k in args) {
        v = args[k];
        if (v instanceof Function) {
          functions[k] = v;
        } else {
          statics[k] = v;
        }
      }
      Override = this.get(keyword);
      if ((Override != null) && (typeof Override.get === "function" ? Override.get('storm') : void 0)) {
        return (function(_super1) {
          __extends(_Class, _super1);

          function _Class() {
            return _Class.__super__.constructor.apply(this, arguments);
          }

          _Class.set({
            storm: keyword
          });

          if (name != null) {
            _Class.set({
              name: name
            });
          }

          _Class.extend(statics);

          _Class.include(functions);

          return _Class;

        })(Override);
      } else {
        return (function(_super1) {
          __extends(_Class, _super1);

          function _Class() {
            return _Class.__super__.constructor.apply(this, arguments);
          }

          _Class.set({
            storm: keyword
          });

          _Class.extend(statics);

          _Class.include(functions);

          return _Class;

        })(YangObject);
      }
    };

    return Yang;

  })(StormClass);

  module.exports = Yang;

}).call(this);