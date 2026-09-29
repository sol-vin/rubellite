require "../c_api"
require "../value"
require "../convert"

module Rubellite
  module Extension
    # Builder for creating native C extensions loadable by CRuby
    class Builder
      getter name : String

      def initialize(@name : String)
      end

      def def_module(mod_name : String, &block)
        # Defines a module in Ruby
        m_val = LibRuby.rb_define_module(mod_name.to_unsafe)
        yield Value.new(m_val)
      end

      def def_class(class_name : String, &block)
        rb_obj = LibRuby.rb_eval_string("Object")
        c_val = LibRuby.rb_define_class(class_name.to_unsafe, rb_obj)
        yield Value.new(c_val)
      end
    end

    # DSL entrypoint for building a Ruby extension in Crystal
    def self.build(name : String, &block : Builder -> Nil) : Nil
      builder = Builder.new(name)
      yield builder
    end
  end
end

# Macro to generate the C-extension entrypoint function `Init_<name>()`
macro ruby_extension(name, &block)
  fun Init_{{name.id}} : Void
    # Initialize Crystal runtime if loaded dynamically by Ruby
    {% if flag?(:windows) %}
      # MSVC / Windows entry initialization
    {% end %}
    Rubellite::Extension.build({{name.stringify}}) do |ext|
      {{block.body}}
    end
  end
end
