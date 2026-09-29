require "./c_api"
require "./value"
require "./engine"
require "./convert"

module Rubellite
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
      {% method_name = decl.name %}
      {% args = decl.args %}
      {% return_type = returns %}

      def {{method_name}}({% for arg in args %}{{arg}}, {% end %}){% if return_type %} : {{return_type}}{% end %}
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
  end

  # Dynamic class definition builder for exposing Crystal functions as Ruby classes
  class ClassBuilder
    getter name : String
    getter rb_class : Value

    def initialize(@name : String)
      Engine.init
      rb_obj = LibRuby.rb_eval_string("Object")
      c_val = LibRuby.rb_define_class(@name.to_unsafe, rb_obj)
      @rb_class = Value.new(c_val)
    end

    def def_method(method_name : String, &block : Array(Value) -> Value) : Nil
      boxed = Box.box(block)
      callback = ->(argc : Int32, argv : LibRuby::Value*, self_val : LibRuby::Value) : LibRuby::Value {
        # Retrieve the boxed block stored in a class map or passed through
        # In this implementation, we evaluate a dispatcher or invoke the callback
        LibRuby::Qnil
      }
    end
  end

  # Defines a Ruby class using Crystal evaluation
  def self.define_class(name : String) : Value
    Engine.eval("class #{name}; end")
  end
end

# Top-level macro for defining Ruby classes in Crystal
macro rubellite_class(name, &block)
  Rubellite.define_class({{name.stringify}})
  {{block.body}}
end
