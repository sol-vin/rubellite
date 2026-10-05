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

    def time? : Bool
      class_name == "Time"
    end

    def range? : Bool
      class_name == "Range"
    end

    def regex? : Bool
      class_name == "Regexp"
    end

    def set? : Bool
      class_name == "Set"
    end

    def rational? : Bool
      class_name == "Rational"
    end

    def complex? : Bool
      class_name == "Complex"
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
        # Fast arithmetic shift for Fixnum tagged pointer (use ! to allow signed negative fixnums)
        (@raw.to_i64! >> 1)
      elsif ruby_nil?
        raise TypeCastError.new("Cannot convert Ruby nil to Int64")
      elsif flonum? || class_name == "Float"
        LibRuby.rb_num2dbl(@raw).to_i64
      elsif class_name == "Integer"
        LibRuby.rb_num2ll(@raw)
      elsif string?
        to_s.to_i64
      else
        res = call("to_i")
        if res.fixnum?
          res.raw.to_i64! >> 1
        else
          LibRuby.rb_num2ll(res.raw)
        end
      end
    end

    def to_i32 : Int32
      to_i64.to_i32
    end

    def to_i : Int32
      to_i32
    end

    def to_f64 : Float64
      if ruby_nil?
        raise TypeCastError.new("Cannot convert Ruby nil to Float64")
      elsif flonum? || fixnum? || class_name == "Float" || class_name == "Integer"
        LibRuby.rb_num2dbl(@raw)
      elsif string?
        to_s.to_f64
      else
        res = call("to_f")
        LibRuby.rb_num2dbl(res.raw)
      end
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

    # Converts Ruby string (including embedded null bytes) to a native Crystal byte slice
    def to_slice : Bytes
      if string?
        copy = @raw
        ptr = LibRuby.rb_string_value_ptr(pointerof(copy))
        len = LibRuby.rb_str_strlen(@raw).to_i32
        return Bytes.empty if len == 0 || ptr.null?
        Bytes.new(len) { |i| ptr[i] }
      else
        to_s.to_slice
      end
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
      if array?
        len = call("length").to_i64
        Array(Value).new(len.to_i32) do |i|
          Value.new(LibRuby.rb_ary_entry(@raw, i))
        end
      else
        call("to_a").to_a
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

    def to_time : Time
      if ruby_nil?
        raise TypeCastError.new("Cannot convert Ruby nil to Time")
      end
      sec = call("to_i").to_i64
      usec = call("usec").to_i64
      Time.unix(sec) + usec.microseconds
    end

    def to_range : Range(Int64, Int64)?
      return nil unless range?
      begin_val = call("begin")
      end_val = call("end")
      return nil if begin_val.ruby_nil? || end_val.ruby_nil?
      exclusive = call("exclude_end?").to_bool
      Range.new(begin_val.to_i64, end_val.to_i64, exclusive)
    end

    def to_set : Set(Value)
      Set(Value).new(to_a)
    end

    # =========================================================================
    # Dynamic Method Invocation
    # =========================================================================

    # Structs to safely pass call arguments into rb_protect callbacks
    private struct FuncallData
      property recv : LibRuby::Value
      property mid : LibRuby::Id
      property argc : Int32
      property argv : LibRuby::Value*
      def initialize(@recv, @mid, @argc, @argv); end
    end

    private struct BlockCallData
      property recv : LibRuby::Value
      property mid : LibRuby::Id
      property argc : Int32
      property argv : LibRuby::Value*
      property callback : (LibRuby::Value, LibRuby::Value, Int32, LibRuby::Value* -> LibRuby::Value)
      property data2 : LibRuby::Value
      def initialize(@recv, @mid, @argc, @argv, @callback, @data2); end
    end

    # Invokes a method on the Ruby object with protected execution
    def call(method_name : String | Symbol, *args) : Value
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

      call_data = FuncallData.new(@raw, mid, argc, raw_args)
      fn = ->(arg : Void*) : LibRuby::Value {
        cd = arg.as(FuncallData*)
        LibRuby.rb_funcallv(cd.value.recv, cd.value.mid, cd.value.argc, cd.value.argv)
      }

      state = 0
      res = Engine.synchronize do
        LibRuby.rb_protect(fn, pointerof(call_data).as(Void*), pointerof(state))
      end
      if state != 0
        raise Error.from_ruby_errinfo
      end
      Value.new(res)
    end

    # Invokes a method while passing a Crystal block as a Ruby block with protected execution
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

      call_data = BlockCallData.new(@raw, mid, argc, raw_args, callback, LibRuby::Value.new(boxed_block.address))
      fn = ->(arg : Void*) : LibRuby::Value {
        bcd = arg.as(BlockCallData*)
        LibRuby.rb_block_call(bcd.value.recv, bcd.value.mid, bcd.value.argc, bcd.value.argv, bcd.value.callback, bcd.value.data2)
      }

      state = 0
      res = Engine.synchronize do
        LibRuby.rb_protect(fn, pointerof(call_data).as(Void*), pointerof(state))
      end
      if state != 0
        raise Error.from_ruby_errinfo
      end
      Value.new(res)
    end

    # Invokes a method with a block, delegating to call_with_block
    def call(method_name : String | Symbol, *args, &block : Array(Value) -> Value) : Value
      call_with_block(method_name, *args, &block)
    end

    # Invokes a method with positional arguments and keyword arguments using Ruby 3+ kwargs protocol
    def call_with_kwargs(method_name : String | Symbol, *args, **kwargs) : Value
      mid = LibRuby.rb_intern(method_name.to_s.to_unsafe)
      kw_hash = Hash(Symbol, Value).new
      kwargs.each do |k, v|
        kw_hash[k] = v.is_a?(Value) ? v : v.to_ruby
      end

      raw_args = Array(LibRuby::Value).new(args.size + 1)
      args.each do |a|
        raw_args << (a.is_a?(Value) ? a.raw : a.to_ruby.raw)
      end
      raw_args << kw_hash.to_ruby.raw

      call_data = FuncallData.new(@raw, mid, raw_args.size, raw_args.to_unsafe)
      fn = ->(arg : Void*) : LibRuby::Value {
        cd = arg.as(FuncallData*)
        LibRuby.rb_funcallv_kw(cd.value.recv, cd.value.mid, cd.value.argc, cd.value.argv, LibRuby::RB_PASS_KEYWORDS)
      }

      state = 0
      res = Engine.synchronize do
        LibRuby.rb_protect(fn, pointerof(call_data).as(Void*), pointerof(state))
      end
      if state != 0
        raise Error.from_ruby_errinfo
      end
      Value.new(res)
    end

    # =========================================================================
    # Collection Access & Operator Overloading
    # =========================================================================

    def size : Int32
      call("length").to_i32
    end

    def length : Int32
      size
    end

    def empty? : Bool
      call("empty?").to_bool
    end

    def keys : Array(Value)
      call("keys").to_a
    end

    def values : Array(Value)
      call("values").to_a
    end

    def has_key?(key) : Bool
      return true if call("key?", key).to_bool
      if key.is_a?(String)
        id = LibRuby.rb_intern(key.to_unsafe)
        sym_val = Value.new((id << 8) | LibRuby::SYMBOL_FLAG)
        call("key?", sym_val).to_bool
      elsif key.is_a?(Symbol)
        call("key?", key.to_s).to_bool
      else
        false
      end
    rescue
      false
    end

    # Safe nested key navigation across Hashes and Arrays (transparently handles String and Symbol keys)
    def dig(*keys) : Value?
      current = self
      keys.each do |k|
        return nil if current.ruby_nil?
        if current.hash?
          val = current[k]
          if val.ruby_nil? && k.is_a?(String)
            id = LibRuby.rb_intern(k.to_unsafe)
            sym_val = Value.new((id << 8) | LibRuby::SYMBOL_FLAG)
            val = current[sym_val]
          elsif val.ruby_nil? && k.is_a?(Symbol)
            val = current[k.to_s]
          end
          current = val
        elsif current.array?
          idx = k.is_a?(Int) ? k : k.to_s.to_i?
          return nil unless idx
          current = current[idx]
        elsif current.respond_to?("[]")
          current = current[k]
        else
          return nil
        end
      end
      current.ruby_nil? ? nil : current
    rescue
      nil
    end

    # Iterates over each element in a Ruby Enumerable / Array
    def each(&block : Value -> Nil) : Nil
      call_with_block("each") do |args|
        block.call(args[0]) if args.size > 0
        Value.new(LibRuby::Qnil)
      end
    end

    # Iterates over key-value pairs in a Ruby Hash
    def each_pair(&block : (Value, Value) -> Nil) : Nil
      call_with_block("each_pair") do |args|
        if args.size >= 2
          block.call(args[0], args[1])
        elsif args.size == 1 && args[0].array?
          pair = args[0].to_a
          block.call(pair[0], pair[1]) if pair.size >= 2
        end
        Value.new(LibRuby::Qnil)
      end
    end

    # Introspection: checks if the Ruby object responds to a method
    def respond_to?(method_name : String | Symbol) : Bool
      call("respond_to?", method_name.to_s).to_bool
    end

    # Introspection: checks if the Ruby object is a kind of a Ruby class
    def kind_of?(class_name : String) : Bool
      klass = Rubellite[class_name]?
      return false unless klass
      call("kind_of?", klass).to_bool
    rescue
      false
    end

    def ruby_is_a?(class_name : String) : Bool
      kind_of?(class_name)
    end

    # Safe method dispatch: returns nil if an exception or NoMethodError occurs
    def call?(method_name : String | Symbol, *args) : Value?
      call(method_name, *args)
    rescue
      nil
    end

    # Alias for call
    def send(method_name : String | Symbol, *args) : Value
      call(method_name, *args)
    end

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
