require "./c_api"
require "./value"
require "./engine"
require "./gc"

module Rubellite
  # Metadata container holding the C-ABI DataType struct, Ruby class reference,
  # and method trampoline table for wrapped types.
  class TypeDescriptor
    property name : String
    property ruby_class : Value
    property handlers : Hash(String, Proc(Void*, Array(Value), Value))
    property data_type_ptr : LibRuby::DataType*

    def initialize(@name : String, @ruby_class : Value)
      @handlers = Hash(String, Proc(Void*, Array(Value), Value)).new

      funcs = LibRuby::DataTypeFunctions.new
      funcs.dmark = Pointer(Void).null
      
      # dfree callback called by CRuby GC during sweep
      dfree_proc = ->(ptr : Void*) {
        if !ptr.null?
          Rubellite::GC.unpin(ptr.address.to_u64)
        end
      }
      funcs.dfree = dfree_proc.pointer.as(Void*)
      funcs.dsize = Pointer(Void).null
      funcs.dcompact = Pointer(Void).null
      funcs.reserved[0] = Pointer(Void).null

      @data_type_ptr = Pointer(LibRuby::DataType).malloc(1)
      @data_type_ptr.value = LibRuby::DataType.new(
        wrap_struct_name: @name.to_unsafe,
        function: funcs,
        parent: Pointer(LibRuby::DataType).null,
        data: Pointer(Void).null,
        flags: LibRuby::Value.new(0)
      )
    end
  end

  # Thread-safe global registry mapping Crystal type names to their TypeDescriptor
  module TypedDataRegistry
    @@registry = Hash(String, TypeDescriptor).new
    @@mutex = Mutex.new

    def self.get(name : String, &block : -> TypeDescriptor) : TypeDescriptor
      if desc = @@mutex.synchronize { @@registry[name]? }
        return desc
      end
      @@mutex.synchronize do
        @@registry[name] ||= yield
      end
    end
  end

  # Coordinates zero-copy object wrapping between Crystal classes/structs and CRuby RTypedData.
  # Guarantees dual-GC safety by pinning Crystal objects in Boehm GC on creation, and unpinning
  # them via the CRuby dfree callback when the Ruby object is swept.
  module TypedData(T)
    # Returns the registered TypeDescriptor for T, initializing it on first access
    def self.info : TypeDescriptor
      TypedDataRegistry.get(T.name) do
        Rubellite.ensure_init!
        type_name = T.name.split("::").last
        
        # Define or resolve class in CRuby
        rb_object = LibRuby.rb_eval_string("Object")
        c_val = LibRuby.rb_define_class(type_name.to_unsafe, rb_object)
        LibRuby.rb_undef_alloc_func(c_val)
        
        TypeDescriptor.new(type_name, Value.new(c_val))
      end
    end

    # Sets a custom Ruby class name for this type
    def self.wrap_name=(name : String) : Nil
      ti = info
      ti.name = name
      ti.data_type_ptr.value.wrap_struct_name = name.to_unsafe
    end

    # Wraps a Crystal object into a CRuby RTypedData Value with zero memory copy
    def self.wrap(obj : T) : Value
      Rubellite.ensure_init!
      ti = info

      # Box the Crystal instance and pin it in Boehm GC
      boxed_ptr = Box(T).box(obj)
      Rubellite::GC.pin(obj)

      raw = LibRuby.rb_data_typed_object_wrap(
        ti.ruby_class.raw,
        boxed_ptr,
        ti.data_type_ptr
      )
      Value.new(raw)
    end

    # Unwraps a CRuby RTypedData Value back into the underlying Crystal instance.
    # Raises `TypeException` if the value does not wrap type T.
    def self.unwrap(val : Value) : T
      Rubellite.ensure_init!
      ti = info
      unless typed_data?(val)
        raise TypeException.new("Expected Ruby TypedData of type #{T.name}, got #{val.class_name}")
      end
      datap = LibRuby.rb_check_typeddata(val.raw, ti.data_type_ptr)
      if datap.null?
        raise TypeException.new("Failed to unwrap TypedData: pointer is null for #{T.name}")
      end
      Box(T).unbox(datap)
    end

    # Safely unwraps a CRuby RTypedData Value, returning nil if the type does not match
    def self.unwrap?(val : Value) : T?
      return nil unless typed_data?(val)
      unwrap(val)
    rescue
      nil
    end

    # Checks if a CRuby Value wraps an instance of T
    def self.typed_data?(val : Value) : Bool
      return false if val.ruby_nil? || val.fixnum? || val.flonum? || val.symbol?
      Rubellite.ensure_init!
      ti = info
      LibRuby.rb_typeddata_is_kind_of(val.raw, ti.data_type_ptr) != 0
    end

    # Defines an instance method on the CRuby class that receives the unwrapped Crystal self
    def self.def_method(method_name : String, &block : T, Array(Value) -> Value) : Nil
      ti = info
      ti.handlers[method_name] = ->(ptr : Void*, args : Array(Value)) : Value {
        obj = Box(T).unbox(ptr)
        block.call(obj, args)
      }

      trampoline = ->(argc : Int32, argv : LibRuby::Value*, self_val : LibRuby::Value) : LibRuby::Value {
        begin
          id = LibRuby.rb_frame_this_func
          name_ptr = LibRuby.rb_id2name(id)
          m_name = name_ptr ? String.new(name_ptr) : ""

          curr_info = TypedData(T).info
          handler = curr_info.handlers[m_name]?
          return LibRuby::Qnil unless handler

          datap = LibRuby.rb_check_typeddata(self_val, curr_info.data_type_ptr)
          return LibRuby::Qnil if datap.null?

          args = Array(Value).new(argc)
          argc.times { |i| args << Value.new(argv[i]) }

          res = handler.call(datap, args)
          res.raw
        rescue ex
          err_klass = LibRuby.rb_eval_string("RuntimeError")
          LibRuby.rb_raise(err_klass, "%s".to_unsafe, (ex.message || "Crystal TypedData method error").to_unsafe)
          LibRuby::Qnil
        end
      }

      LibRuby.rb_define_method(ti.ruby_class.raw, method_name.to_unsafe, trampoline.pointer.as(Void*), -1)
    end
  end

  # Mixin module to easily enable TypedData wrapping on any Crystal class or struct
  module TypedDataMixin
    # Converts this Crystal object to a CRuby RTypedData Value
    def to_ruby : Value
      Rubellite::TypedData(typeof(self)).wrap(self)
    end
  end

  # Convenience wrapper at the Rubellite top level
  def self.wrap(obj : T) : Value forall T
    TypedData(T).wrap(obj)
  end

  # Convenience unwrap at the Rubellite top level
  def self.unwrap(type : T.class, val : Value) : T forall T
    TypedData(T).unwrap(val)
  end

  # Convenience safe unwrap at the Rubellite top level
  def self.unwrap?(type : T.class, val : Value) : T? forall T
    TypedData(T).unwrap?(val)
  end

  struct Value
    # Unwraps this Ruby Value into a Crystal TypedData instance of type T.
    # Raises TypeException if the Value does not wrap type T.
    def as_typed_data(type : T.class) : T forall T
      Rubellite::TypedData(T).unwrap(self)
    end

    # Safely unwraps this Ruby Value into a Crystal TypedData instance, returning nil on type mismatch.
    def as_typed_data?(type : T.class) : T? forall T
      Rubellite::TypedData(T).unwrap?(self)
    end

    # Checks if this Ruby Value is a TypedData wrapping type T.
    def typed_data?(type : T.class) : Bool forall T
      Rubellite::TypedData(T).typed_data?(self)
    end
  end
end
