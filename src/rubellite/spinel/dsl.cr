module Rubellite
  module Spinel
    # High-level declarative DSL for embedding native C/Spinel kernels directly in Crystal.
  end
end

# Top-level macro for defining high-performance Spinel native C methods
macro spinel_c(decl, returns, code)
  {% method_name = decl.name %}
  {% args = decl.args %}
  {% ret_type = returns %}

  # Class/Module variable to hold compiled native function pointer
  @@__spinel_fn_{{method_name.id}} : Rubellite::Spinel::NativeFunction? = nil

  def self.{{method_name.id}}({% for arg, i in args %}{% if i > 0 %}, {% end %}{{arg}}{% end %}) : {{ret_type}}
    fn = @@__spinel_fn_{{method_name.id}} ||= begin
      c_source = String.build do |io|
        io << "#include <stdint.h>\n#include <stdbool.h>\n#include <stdlib.h>\n#include <math.h>\n\n"
        io << "#ifdef _WIN32\n#define EXPORT __declspec(dllexport)\n#else\n#define EXPORT __attribute__((visibility(\"default\")))\n#endif\n\n"
        io << "EXPORT "
        io << case {{ret_type.stringify}}
              when "Int64" then "int64_t"
              when "Int32" then "int32_t"
              when "UInt64" then "uint64_t"
              when "UInt32" then "uint32_t"
              when "Float64" then "double"
              when "Float32" then "float"
              when "Bool" then "bool"
              when "Void", "Nil" then "void"
              else "void*"
              end
        io << " " << {{method_name.stringify}} << "("
        {% for arg, i in args %}
          {% if i > 0 %} io << ", "; {% end %}
          io << case {{arg.type.stringify}}
                when "Int64" then "int64_t"
                when "Int32" then "int32_t"
                when "UInt64" then "uint64_t"
                when "UInt32" then "uint32_t"
                when "Float64" then "double"
                when "Float32" then "float"
                when "Bool" then "bool"
                else "void*"
                end
          io << " " << {{arg.var.stringify}}
        {% end %}
        io << ") {\n"
        io << {{code}} << "\n"
        io << "}\n"
      end

      Rubellite::Spinel.compile_c_function(
        c_source,
        {{method_name.stringify}},
        {{ret_type.stringify}}
      )
    end

    {% if ret_type.stringify == "Float64" %}
      fn.call_f64({% for arg, i in args %}{% if i > 0 %}, {% end %}{{arg.var}}{% end %})
    {% elsif ret_type.stringify == "Float32" %}
      fn.call_f32({% for arg, i in args %}{% if i > 0 %}, {% end %}{{arg.var}}{% end %})
    {% elsif ret_type.stringify == "Int32" %}
      fn.call_i32({% for arg, i in args %}{% if i > 0 %}, {% end %}{{arg.var}}{% end %})
    {% elsif ret_type.stringify == "Bool" %}
      fn.call_bool({% for arg, i in args %}{% if i > 0 %}, {% end %}{{arg.var}}{% end %})
    {% elsif ret_type.stringify == "Void" || ret_type.stringify == "Nil" %}
      fn.call_void({% for arg, i in args %}{% if i > 0 %}, {% end %}{{arg.var}}{% end %})
      nil
    {% else %}
      fn.call_i64({% for arg, i in args %}{% if i > 0 %}, {% end %}{{arg.var}}{% end %})
    {% end %}
  end
end

# Macro for grouping multiple Spinel kernels into a typed module
macro spinel_module(name, &block)
  module {{name.id}}
    {{block.body}}
  end
end
