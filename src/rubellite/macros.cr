require "./c_api"
require "./value"
require "./engine"
require "./convert"

module Rubellite
  # Internal dispatcher for Crystal procs exported to CRuby
  module ExportDispatcher
    @@lock = Mutex.new
    @@singleton_methods = Hash(String, (Array(Value) -> Value)).new
    @@instance_methods = Hash(Tuple(String, String), (Array(Value) -> Value)).new

    def self.register_singleton(name : String, &block : Array(Value) -> Value)
      @@lock.synchronize do
        @@singleton_methods[name] = block
      end
    end

    def self.register_instance(klass : String, name : String, &block : Array(Value) -> Value)
      @@lock.synchronize do
        @@instance_methods[{klass, name}] = block
      end
    end

    def self.dispatch_singleton(argc : Int32, argv : LibRuby::Value*, self_val : LibRuby::Value) : LibRuby::Value
      id = LibRuby.rb_frame_this_func
      name_ptr = LibRuby.rb_id2name(id)
      return LibRuby::Qnil unless name_ptr
      method_name = String.new(name_ptr)

      handler = @@lock.synchronize { @@singleton_methods[method_name]? }
      return LibRuby::Qnil unless handler

      args = Array(Value).new(argc)
      argc.times { |i| args << Value.new(argv[i]) }

      begin
        res = handler.call(args)
        res.raw
      rescue ex
        err_klass = LibRuby.rb_eval_string("RuntimeError")
        LibRuby.rb_raise(err_klass, ex.message || "Crystal callback error")
        LibRuby::Qnil
      end
    end

    def self.dispatch_instance(argc : Int32, argv : LibRuby::Value*, self_val : LibRuby::Value) : LibRuby::Value
      id = LibRuby.rb_frame_this_func
      name_ptr = LibRuby.rb_id2name(id)
      return LibRuby::Qnil unless name_ptr
      method_name = String.new(name_ptr)

      c_name_ptr = LibRuby.rb_obj_classname(self_val)
      class_name = c_name_ptr ? String.new(c_name_ptr) : ""

      handler = @@lock.synchronize { @@instance_methods[{class_name, method_name}]? }
      return LibRuby::Qnil unless handler

      args = Array(Value).new(argc)
      argc.times { |i| args << Value.new(argv[i]) }

      begin
        res = handler.call(args)
        res.raw
      rescue ex
        err_klass = LibRuby.rb_eval_string("RuntimeError")
        LibRuby.rb_raise(err_klass, ex.message || "Crystal callback error")
        LibRuby::Qnil
      end
    end
  end

  # Base class for strongly typed proxies wrapping Ruby objects
  abstract class Proxy
    getter ruby_value : Value

    def initialize(@ruby_value : Value)
    end

    def self.target_class_name : String
      ""
    end

    # Macro to specify which Ruby class this proxy wraps
    macro ruby_target(class_name)
      def self.target_class_name : String
        {{class_name}}
      end

      def self.new(raw_obj : Rubellite::Value)
        inst = allocate
        inst.initialize(raw_obj)
        inst
      end

      def self.new
        raw_obj = Rubellite[target_class_name].call("new")
        new(raw_obj)
      end

      def self.new(*args)
        raw_obj = Rubellite[target_class_name].call("new", *args)
        new(raw_obj)
      end
    end

    # Macro to declare typed methods forwarded to Ruby
    macro ruby_method(decl, returns = nil)
      {% if decl.is_a?(TypeDeclaration) %}
        {% method_call = decl.var %}
        {% return_type = decl.type %}
      {% else %}
        {% method_call = decl %}
        {% return_type = returns %}
      {% end %}

      {% if method_call.is_a?(Call) %}
        {% method_name = method_call.name %}
        {% args = method_call.args %}
      {% else %}
        {% method_name = method_call %}
        {% args = [] of ASTNode %}
      {% end %}

      def {{method_name.id}}({% for arg in args %}{{arg}}, {% end %}){% if return_type %} : {{return_type}}{% end %}
        raw_res = @ruby_value.call({{method_name.stringify}}{% for arg in args %}, {{arg.is_a?(TypeDeclaration) ? arg.var : arg}}{% end %})
        {% if return_type && return_type.stringify == "Int64" %}
          raw_res.to_i64
        {% elsif return_type && return_type.stringify == "Int32" %}
          raw_res.to_i32
        {% elsif return_type && return_type.stringify == "Float64" %}
          raw_res.to_f64
        {% elsif return_type && return_type.stringify == "String" %}
          raw_res.to_s
        {% elsif return_type && return_type.stringify == "Bool" %}
          raw_res.to_bool
        {% elsif return_type && (return_type.stringify == "Value" || return_type.stringify == "Rubellite::Value") %}
          raw_res
        {% elsif return_type %}
          raw_res.as_crystal.as({{return_type}})
        {% else %}
          raw_res
        {% end %}
      end
    end

    # Macro to declare a getter method forwarded to Ruby attribute
    macro ruby_getter(decl, returns = nil)
      {% if decl.is_a?(TypeDeclaration) %}
        ruby_method {{decl.var}}, returns: {{decl.type}}
      {% else %}
        ruby_method {{decl}}, returns: {{returns}}
      {% end %}
    end

    # Macro to declare a setter method forwarded to Ruby attribute
    macro ruby_setter(decl, type = nil)
      {% if decl.is_a?(TypeDeclaration) %}
        {% var_name = decl.var %}
        {% var_type = decl.type %}
      {% else %}
        {% var_name = decl %}
        {% var_type = type %}
      {% end %}
      def {{var_name.id}}=({% if var_type %}val : {{var_type}}{% else %}val{% end %})
        @ruby_value.call("{{var_name.id}}=", val)
      end
    end

    # Macro to declare a combined getter and setter property
    macro ruby_property(decl, type = nil)
      {% if decl.is_a?(TypeDeclaration) %}
        ruby_getter {{decl.var}}, returns: {{decl.type}}
        ruby_setter {{decl.var}}, type: {{decl.type}}
      {% else %}
        ruby_getter {{decl}}, returns: {{type}}
        ruby_setter {{decl}}, type: {{type}}
      {% end %}
    end
  end

  # Dynamic class definition builder for exposing Crystal functions as Ruby classes
  class ClassBuilder
    getter name : String
    getter rb_class : Value

    def initialize(@name : String)
      Rubellite.ensure_init!
      rb_obj = LibRuby.rb_eval_string("Object")
      c_val = LibRuby.rb_define_class(@name.to_unsafe, rb_obj)
      @rb_class = Value.new(c_val)
    end

    def def_method(method_name : String, &block : Array(Value) -> Value) : Nil
      ExportDispatcher.register_instance(@name, method_name, &block)
      fn = ->(argc : Int32, argv : LibRuby::Value*, self_val : LibRuby::Value) : LibRuby::Value {
        ExportDispatcher.dispatch_instance(argc, argv, self_val)
      }
      LibRuby.rb_define_method(@rb_class.raw, method_name.to_unsafe, fn.pointer.as(Void*), -1)
    end
  end

  # Defines a Ruby class using Crystal evaluation
  def self.define_class(name : String) : Value
    Engine.eval("class #{name}; end")
  end

  # Exports a Crystal function to Ruby under the Rubellite module
  def self.export(method_name : String, &block : Array(Value) -> Value) : Nil
    ensure_init!
    mod_val = LibRuby.rb_define_module("Rubellite")
    ExportDispatcher.register_singleton(method_name, &block)
    fn = ->(argc : Int32, argv : LibRuby::Value*, self_val : LibRuby::Value) : LibRuby::Value {
      ExportDispatcher.dispatch_singleton(argc, argv, self_val)
    }
    LibRuby.rb_define_singleton_method(mod_val, method_name.to_unsafe, fn.pointer.as(Void*), -1)
  end
end

# Top-level macro for defining Ruby classes in Crystal
macro rubellite_class(name, &block)
  Rubellite.define_class({{name.stringify}})
  {{block.body}}
end
