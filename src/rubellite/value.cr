require "./c_api"
require "./exception"

module Rubellite
  # Represents a first-class Ruby value (equivalent to Ruby's C `VALUE`).
  # Provides transparent type checks, unboxing to Crystal primitives,
  # dynamic method dispatch, operator overloads, and block execution.
  struct Value
    getter raw : LibRuby::Value

    def initialize(@raw : LibRuby::Value)
    end

    # =========================================================================
    # Type Inquiries
    # =========================================================================

    def ruby_nil? : Bool
      @raw == LibRuby::Qnil
    end

    def true? : Bool
      @raw == LibRuby::Qtrue
    end

    def false? : Bool
      @raw == LibRuby::Qfalse
    end

    def bool? : Bool
      true? || false?
    end

    # Ruby truthiness: false and nil are falsey, everything else is truthy
    def to_bool : Bool
      @raw != LibRuby::Qnil && @raw != LibRuby::Qfalse
    end

    def fixnum? : Bool
      (@raw & LibRuby::FIXNUM_FLAG) != 0_u64
    end

    def flonum? : Bool
      (@raw & LibRuby::FLONUM_MASK) == LibRuby::FLONUM_FLAG
    end

    def numeric? : Bool
      fixnum? || flonum? || class_name == "Float" || class_name == "Integer"
    end

    def symbol? : Bool
      (@raw & 0xff_u64) == LibRuby::SYMBOL_FLAG
    end

    def string? : Bool
      class_name == "String"
    end

    def array? : Bool
      class_name == "Array"
    end

    def hash? : Bool
      class_name == "Hash"
    end

    def proc? : Bool
      class_name == "Proc"
    end

    def class_name : String
      return "NilClass" if ruby_nil?
      return "TrueClass" if true?
      return "FalseClass" if false?
      return "Integer" if fixnum?
      return "Float" if flonum?
      return "Symbol" if symbol?

      c_name = LibRuby.rb_obj_classname(@raw)
      c_name ? String.new(c_name) : "Object"
    end

    # =========================================================================
    # Unboxing to Crystal Types
    # =========================================================================

    def to_i64 : Int64
      if fixnum?
        # Fast arithmetic shift for Fixnum tagged pointer
        (@raw.to_i64 >> 1)
      else
        LibRuby.rb_num2ll(@raw)
      end
    end

    def to_i32 : Int32
      to_i64.to_i32
    end

    def to_i : Int32
      to_i32
    end

    def to_f64 : Float64
      LibRuby.rb_num2dbl(@raw)
    end

    def to_f : Float64
      to_f64
    end

    def to_s(io : IO) : Nil
      if string?
        copy = @raw
        cstr = LibRuby.rb_string_value_cstr(pointerof(copy))
        io << (cstr ? String.new(cstr) : "")
      elsif ruby_nil?
        io << ""
      else
        io << call("to_s").to_s
      end
    end

    def to_s : String
      String.build { |io| to_s(io) }
    end

    def inspect(io : IO) : Nil
      inspected = LibRuby.rb_inspect(@raw)
      cstr = LibRuby.rb_string_value_cstr(pointerof(inspected))
      io << (cstr ? String.new(cstr) : "<Ruby::Value>")
    end

    def inspect : String
      String.build { |io| inspect(io) }
    end

    def symbol_name : String
      if symbol?
        id = @raw >> 8
        cstr = LibRuby.rb_id2name(id)
        cstr ? String.new(cstr) : ""
      else
        to_s
      end
    end

    def to_sym : String
      symbol_name
    end

    def to_a : Array(Value)
      len = call("length").to_i64
      Array(Value).new(len.to_i32) do |i|
        Value.new(LibRuby.rb_ary_entry(@raw, i))
      end
    end

    def to_h : Hash(Value, Value)
      result = Hash(Value, Value).new
      keys = call("keys").to_a
      keys.each do |k|
        result[k] = self[k]
      end
      result
    end

    # =========================================================================
    # Dynamic Method Invocation
    # =========================================================================

    # Invokes a method on the Ruby object
    def call(method_name : String | Symbol, *args) : Value
      mid = LibRuby.rb_intern(method_name.to_s.to_unsafe)
      argc = args.size
      if argc == 0
        res = LibRuby.rb_funcallv(@raw, mid, 0, Pointer(LibRuby::Value).null)
      else
        raw_args = Array(LibRuby::Value).new(argc)
        args.each do |a|
          raw_args << (a.is_a?(Value) ? a.raw : a.to_ruby.raw)
        end
        res = LibRuby.rb_funcallv(@raw, mid, argc, raw_args.to_unsafe)
      end
      Value.new(res)
    end

    # Invokes a method while passing a Crystal block as a Ruby block
    def call_with_block(method_name : String | Symbol, *args, &block : Array(Value) -> Value) : Value
      mid = LibRuby.rb_intern(method_name.to_s.to_unsafe)
      argc = args.size
      raw_args_ary = if argc > 0
                       arr = Array(LibRuby::Value).new(argc)
                       args.each do |a|
                         arr << (a.is_a?(Value) ? a.raw : a.to_ruby.raw)
                       end
                       arr
                     else
                       nil
                     end
      raw_args = raw_args_ary ? raw_args_ary.to_unsafe : Pointer(LibRuby::Value).null

      # Box the Crystal block so the C callback can invoke it
      boxed_block = Box.box(block)

      callback = ->(yielded_arg : LibRuby::Value, data : LibRuby::Value, argc : Int32, argv : LibRuby::Value*) : LibRuby::Value {
        proc = Box(typeof(block)).unbox(Pointer(Void).new(data))
        values = [] of Value
        if argc > 0 && argv
          argc.times { |i| values << Value.new(argv[i]) }
        elsif yielded_arg != LibRuby::Qundef
          values << Value.new(yielded_arg)
        end
        proc.call(values).raw
      }

      res = LibRuby.rb_block_call(@raw, mid, argc, raw_args, callback, LibRuby::Value.new(boxed_block.address))
      Value.new(res)
    end

    # =========================================================================
    # Collection Access & Operator Overloading
    # =========================================================================

    def [](key) : Value
      call("[]", key)
    end

    def []=(key, val) : Value
      call("[]=", key, val)
    end

    def +(other) : Value
      call("+", other)
    end

    def -(other) : Value
      call("-", other)
    end

    def *(other) : Value
      call("*", other)
    end

    def /(other) : Value
      call("/", other)
    end

    def ==(other : Value) : Bool
      @raw == other.raw || call("==", other).to_bool
    end

    def ==(other) : Bool
      call("==", other).to_bool
    end

    def <(other) : Bool
      call("<", other).to_bool
    end

    def <=(other) : Bool
      call("<=", other).to_bool
    end

    def >(other) : Bool
      call(">", other).to_bool
    end

    def >=(other) : Bool
      call(">=", other).to_bool
    end
  end
end
