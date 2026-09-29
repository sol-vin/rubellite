{% if flag?(:windows) %}
  @[Link(ldflags: "\"#{__DIR__}/../../ext/ruby_clean.lib\"")]
{% elsif flag?(:darwin) %}
  @[Link(ldflags: "`pkg-config --libs ruby-3.4 2>/dev/null || pkg-config --libs ruby-3.3 2>/dev/null || pkg-config --libs ruby-3.2 2>/dev/null || pkg-config --libs ruby 2>/dev/null || echo -lruby`")]
{% else %}
  @[Link(ldflags: "`pkg-config --libs ruby-3.4 2>/dev/null || pkg-config --libs ruby-3.3 2>/dev/null || pkg-config --libs ruby-3.2 2>/dev/null || pkg-config --libs ruby 2>/dev/null || echo -lruby`")]
{% end %}
lib LibRuby
  alias Value = UInt64
  alias Id = UInt64

  # Special Constants (64-bit with USE_FLONUM)
  Qfalse = 0x00_u64
  Qnil   = 0x04_u64
  Qtrue  = 0x14_u64
  Qundef = 0x24_u64

  IMMEDIATE_MASK = 0x07_u64
  FIXNUM_FLAG    = 0x01_u64
  FLONUM_MASK    = 0x03_u64
  FLONUM_FLAG    = 0x02_u64
  SYMBOL_FLAG    = 0x0c_u64

  # VM Lifecycle
  fun ruby_sysinit(argc : Int32*, argv : UInt8***) : Void
  fun ruby_init_stack(addr : Void*) : Void
  fun ruby_init : Void
  fun ruby_init_loadpath : Void
  fun ruby_cleanup(code : Int32) : Int32
  fun ruby_finalize : Void

  # Eval & Protect
  fun rb_eval_string(str : UInt8*) : Value
  fun rb_eval_string_protect(str : UInt8*, state : Int32*) : Value
  fun rb_protect(func : (Void* -> Value), data : Void*, state : Int32*) : Value

  # Symbols & Identifiers
  fun rb_intern(name : UInt8*) : Id
  fun rb_id2name(id : Id) : UInt8*

  # Numbers
  fun rb_int2inum(n : Int64) : Value
  fun rb_num2ll(val : Value) : Int64
  fun rb_float_new(d : Float64) : Value
  fun rb_num2dbl(val : Value) : Float64

  # Strings
  fun rb_str_new(ptr : UInt8*, len : Int64) : Value
  fun rb_str_new_cstr(ptr : UInt8*) : Value
  fun rb_string_value_cstr(ptr : Value*) : UInt8*

  # Arrays
  fun rb_ary_new : Value
  fun rb_ary_new_capa(capa : Int64) : Value
  fun rb_ary_push(ary : Value, item : Value) : Value
  fun rb_ary_entry(ary : Value, offset : Int64) : Value

  # Hashes
  fun rb_hash_new : Value
  fun rb_hash_aset(hash : Value, key : Value, val : Value) : Value
  fun rb_hash_aref(hash : Value, key : Value) : Value
  fun rb_hash_size(hash : Value) : Value

  # Method Dispatch & Callbacks
  fun rb_funcallv(obj : Value, mid : Id, argc : Int32, argv : Value*) : Value
  fun rb_funcallv_public(obj : Value, mid : Id, argc : Int32, argv : Value*) : Value
  fun rb_block_call(obj : Value, mid : Id, argc : Int32, argv : Value*, blk : (Value, Value, Int32, Value* -> Value), data2 : Value) : Value
  fun rb_yield(val : Value) : Value
  fun rb_yield_values(n : Int32, ...) : Value
  fun rb_block_given_p : Int32

  # Classes & Modules
  fun rb_define_class(name : UInt8*, superclass : Value) : Value
  fun rb_define_module(name : UInt8*) : Value
  fun rb_define_method(klass : Value, name : UInt8*, func : Void*, argc : Int32) : Void
  fun rb_define_singleton_method(klass : Value, name : UInt8*, func : Void*, argc : Int32) : Void
  fun rb_const_get(klass : Value, id : Id) : Value
  fun rb_obj_classname(obj : Value) : UInt8*
  fun rb_inspect(val : Value) : Value

  # Exceptions
  fun rb_errinfo : Value
  fun rb_set_errinfo(err : Value) : Void
  fun rb_raise(exc : Value, fmt : UInt8*, ...) : Void

  # Garbage Collection
  fun rb_gc_register_address(val : Value*) : Void
  fun rb_gc_unregister_address(val : Value*) : Void
  fun rb_gc_mark(val : Value) : Void
  fun rb_gc_start : Void

  # GVL Management
  fun rb_thread_call_without_gvl(
    func : (Void* -> Void*),
    data1 : Void*,
    ubf : Void*,
    data2 : Void*
  ) : Void*

  fun rb_thread_call_with_gvl(
    func : (Void* -> Void*),
    data1 : Void*
  ) : Void*
end
