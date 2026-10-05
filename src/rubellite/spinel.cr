require "./value"
require "./convert"
require "./engine"
require "./macros"
require "./spinel/transpiler"
require "./spinel/channel"
require "./spinel/async"
require "./spinel/dsl"
require "./spinel/vector"
require "digest/sha256"

module Rubellite
  # Integration module for Matz's Spinel ahead-of-time Ruby compiler.
  # Compiles Ruby code or raw C kernels into native machine code, built into a shared library,
  # and called directly via pure C ABI function pointers with zero VM overhead.
  module Spinel
    # Supported primitive types for Spinel kernel signatures
    enum Type
      Int32
      Int64
      UInt32
      UInt64
      Float32
      Float64
      Bool
      Void
      Pointer
      String

      def to_c : ::String
        case self
        when Int32   then "int32_t"
        when Int64   then "int64_t"
        when UInt32  then "uint32_t"
        when UInt64  then "uint64_t"
        when Float32 then "float"
        when Float64 then "double"
        when Bool    then "bool"
        when Void    then "void"
        when Pointer then "void*"
        when String  then "const char*"
        else "void*"
        end
      end

      def self.from_string(type_name : ::String) : Type
        case type_name
        when "Int32", "int32_t", "int"         then Int32
        when "Int64", "int64_t", "long long"   then Int64
        when "UInt32", "uint32_t", "unsigned"  then UInt32
        when "UInt64", "uint64_t"              then UInt64
        when "Float32", "float"                then Float32
        when "Float64", "double"               then Float64
        when "Bool", "bool"                    then Bool
        when "Void", "Nil", "void"             then Void
        when "String", "char*"                 then String
        else Pointer
        end
      end
    end

    # Rich compilation diagnostic exception raised when C compiler encounters errors
    class CompilationError < Exception
      getter compiler : String
      getter command : String
      getter details : String
      getter source_code : String

      def initialize(@compiler : String, @command : String, @details : String, @source_code : String)
        annotated = @source_code.lines.map_with_index { |l, i| sprintf("%3d | %s", i + 1, l) }.join("\n")
        super("Spinel compilation failed using '#{@compiler}':\n#{@details}\n\nGenerated Source Unit:\n#{annotated}")
      end
    end

    # Represents a compiled native function from a Spinel module
    class NativeFunction
      getter name : String
      getter lib_handle : Void*
      getter fn_ptr : Void*
      getter return_type_name : String

      def initialize(@name : String, @lib_handle : Void*, @fn_ptr : Void*, @return_type_name : String = "Int64")
      end

      # High-performance direct C-ABI invocation
      # Dispatches dynamically based on configured return type
      def call(*args)
        case @return_type_name
        when "Float64", "double"
          call_f64(*args)
        when "Float32", "float"
          call_f32(*args)
        when "Int32", "int32_t"
          call_i32(*args)
        when "UInt64", "uint64_t"
          call_u64(*args)
        when "UInt32", "uint32_t"
          call_u32(*args)
        when "Bool", "bool"
          call_bool(*args)
        when "Void", "Nil", "void"
          call_void(*args)
          nil
        when "Pointer", "Pointer(Void)", "void*"
          call_ptr(*args)
        else
          call_i64(*args)
        end
      end

      def call_i64(*args) : Int64
        Proc(*typeof(args), Int64).new(@fn_ptr, Pointer(Void).null).call(*args)
      end

      def call_i32(*args) : Int32
        Proc(*typeof(args), Int32).new(@fn_ptr, Pointer(Void).null).call(*args)
      end

      def call_u64(*args) : UInt64
        Proc(*typeof(args), UInt64).new(@fn_ptr, Pointer(Void).null).call(*args)
      end

      def call_u32(*args) : UInt32
        Proc(*typeof(args), UInt32).new(@fn_ptr, Pointer(Void).null).call(*args)
      end

      def call_f64(*args) : Float64
        Proc(*typeof(args), Float64).new(@fn_ptr, Pointer(Void).null).call(*args)
      end

      def call_f32(*args) : Float32
        Proc(*typeof(args), Float32).new(@fn_ptr, Pointer(Void).null).call(*args)
      end

      def call_bool(*args) : Bool
        Proc(*typeof(args), Bool).new(@fn_ptr, Pointer(Void).null).call(*args)
      end

      def call_void(*args) : Nil
        Proc(*typeof(args), Nil).new(@fn_ptr, Pointer(Void).null).call(*args)
      end

      def call_ptr(*args) : Void*
        Proc(*typeof(args), Void*).new(@fn_ptr, Pointer(Void).null).call(*args)
      end

      def call_as(type : T.class, *args) : T forall T
        Proc(*typeof(args), T).new(@fn_ptr, Pointer(Void).null).call(*args)
      end
    end

    # Multi-function native C kernel container
    class Kernel
      getter name : String
      getter lib_path : String
      getter handle : Void*
      getter source_code : String

      def initialize(@name : String, @lib_path : String, @handle : Void*, @source_code : String = "")
      end

      # Calls an exported symbol dynamically, defaulting to Int64 return
      def call(func_name : String, *args) : Int64
        call_as(Int64, func_name, *args)
      end

      # Calls an exported symbol with explicit return type
      def call_as(return_type : T.class, func_name : String, *args) : T forall T
        fn_ptr = DynLink.sym(@handle, func_name)
        raise "Exported symbol '#{func_name}' not found in Spinel kernel '#{@name}'" if fn_ptr.null?
        Proc(*typeof(args), T).new(fn_ptr, Pointer(Void).null).call(*args)
      end

      # Returns a callable NativeFunction handle for a specific exported symbol
      def function(func_name : String, return_type : String = "Int64") : NativeFunction
        fn_ptr = DynLink.sym(@handle, func_name)
        raise "Exported symbol '#{func_name}' not found in Spinel kernel '#{@name}'" if fn_ptr.null?
        NativeFunction.new(func_name, @handle, fn_ptr, return_type)
      end

      # Exports a function from this kernel directly into embedded CRuby as a singleton method
      def export_to_ruby(
        ruby_class_or_mod : String,
        ruby_method_name : String,
        c_func_name : String,
        param_types : Array(String) = [] of String,
        return_type : String = "Int64"
      ) : Nil
        Rubellite.ensure_init!
        fn_obj = function(c_func_name, return_type)

        target_mod = LibRuby.rb_define_module(ruby_class_or_mod)

        block = ->(args : Array(Value)) : Value {
          case {args.size, return_type}
          when {0, "Float64"}, {0, "double"}
            fn_obj.call_f64.to_ruby
          when {0, _}
            fn_obj.call_i64.to_ruby
          when {1, "Float64"}, {1, "double"}
            a0 = (param_types.first? == "Float64" || args[0].float?) ? args[0].to_f64 : args[0].to_i64.to_f64
            fn_obj.call_f64(a0).to_ruby
          when {1, "Int32"}, {1, "int32_t"}
            fn_obj.call_i32(args[0].to_i32).to_ruby
          when {1, "Bool"}, {1, "bool"}
            fn_obj.call_bool(args[0].to_i64).to_ruby
          when {1, _}
            fn_obj.call_i64(args[0].to_i64).to_ruby
          when {2, "Float64"}, {2, "double"}
            a0 = (param_types[0]? == "Float64" || args[0].float?) ? args[0].to_f64 : args[0].to_i64.to_f64
            a1 = (param_types[1]? == "Float64" || args[1].float?) ? args[1].to_f64 : args[1].to_i64.to_f64
            fn_obj.call_f64(a0, a1).to_ruby
          when {2, _}
            fn_obj.call_i64(args[0].to_i64, args[1].to_i64).to_ruby
          when {3, "Float64"}, {3, "double"}
            fn_obj.call_f64(args[0].to_f64, args[1].to_f64, args[2].to_f64).to_ruby
          when {3, _}
            fn_obj.call_i64(args[0].to_i64, args[1].to_i64, args[2].to_i64).to_ruby
          else
            fn_obj.call_i64(args[0].to_i64, args[1].to_i64, args[2].to_i64, args[3].to_i64).to_ruby
          end
        }

        ExportDispatcher.register_singleton(ruby_method_name, &block)
        dispatcher_fn = ->(argc : Int32, argv : LibRuby::Value*, self_val : LibRuby::Value) : LibRuby::Value {
          ExportDispatcher.dispatch_singleton(argc, argv, self_val)
        }
        LibRuby.rb_define_singleton_method(target_mod, ruby_method_name.to_unsafe, dispatcher_fn.pointer.as(Void*), -1)
      end

      # Radare2 machine code disassembly inspection
      def disassemble(func_name : String? = nil) : String
        r2_bin = Diagnostics::R2.find_r2_exe
        unless Process.find_executable(r2_bin) || File.file?(r2_bin)
          return "Disassembly for '#{func_name || @name}' unavailable (radare2 executable not found)"
        end
        target = func_name || @name
        stdout = IO::Memory.new
        stderr = IO::Memory.new
        status = Process.run(r2_bin, args: ["-q", "-2", "-c", "aaa; s sym.#{target}; pdf", @lib_path], output: stdout, error: stderr)
        out_str = stdout.to_s.presence || stderr.to_s.presence
        out_str || "Disassembly for '#{target}' unavailable (radare2 output empty)"
      rescue
        "Disassembly for '#{func_name || @name}' unavailable (radare2 not installed or symbol not found)"
      end

      # Asynchronously executes the C kernel function on a background fiber without blocking the caller
      def async(return_type : T.class, func_name : String, *args) : Future(T) forall T
        future = Future(T).new
        spawn do
          begin
            res = Concurrency.without_gvl do
              call_as(T, func_name, *args)
            end
            future.complete(res)
          rescue ex
            future.fail(ex)
          end
        end
        future
      end

      # Streams real-time data from a C kernel into a Crystal Channel(T)
      def stream(item_type : T.class, func_name : String, *args, capacity : Int32 = 64) : Channel(T) forall T
        channel = Channel(T).new(capacity)
        bridge = ChannelBridge(T).new(channel)
        context = bridge.to_c_context

        spawn do
          begin
            Concurrency.without_gvl do
              fn_ptr = DynLink.sym(@handle, func_name)
              raise "Exported symbol '#{func_name}' not found in Spinel kernel '#{@name}'" if fn_ptr.null?
              Proc(*typeof(args), Pointer(ChannelContext), Nil).new(fn_ptr, Pointer(Void).null).call(*args, pointerof(context))
            end
          rescue ex
            # Handle potential background fiber errors
          ensure
            bridge.close
          end
        end

        channel
      end

      # Connects an input channel to a C processing kernel that streams to an output channel
      def pipe(
        input_channel : Channel(U),
        output_type : V.class,
        func_name : String,
        *args,
        capacity : Int32 = 64
      ) : Channel(V) forall U, V
        out_channel = Channel(V).new(capacity)
        in_bridge = ChannelBridge(U).new(input_channel)
        out_bridge = ChannelBridge(V).new(out_channel)
        in_ctx = in_bridge.to_c_context
        out_ctx = out_bridge.to_c_context

        spawn do
          begin
            Concurrency.without_gvl do
              fn_ptr = DynLink.sym(@handle, func_name)
              raise "Exported symbol '#{func_name}' not found in Spinel kernel '#{@name}'" if fn_ptr.null?
              Proc(*typeof(args), Pointer(ChannelContext), Pointer(ChannelContext), Nil).new(fn_ptr, Pointer(Void).null).call(
                *args,
                pointerof(in_ctx),
                pointerof(out_ctx)
              )
            end
          ensure
            out_bridge.close
          end
        end

        out_channel
      end

      # Calls a C function passing a Crystal callback closure and its context
      def call_with_callback(func_name : String, *args, &block : Int64, Int64 -> Nil) : Nil
        fn_ptr = DynLink.sym(@handle, func_name)
        raise "Exported symbol '#{func_name}' not found in Spinel kernel '#{@name}'" if fn_ptr.null?
        boxed = Box(typeof(block)).box(block)
        trampoline = ->(ctx : Void*, a : Int64, b : Int64) : Nil {
          blk = Box(typeof(block)).unbox(ctx)
          blk.call(a, b)
          nil
        }
        Proc(*typeof(args), Void*, (Void*, Int64, Int64 -> Nil), Nil).new(fn_ptr, Pointer(Void).null).call(
          *args,
          boxed,
          trampoline
        )
      end

      def close
        DynLink.close(@handle) unless @handle.null?
      end
    end

    # High-level engine interface documented in README.md
    module Engine
      def self.compile_function(
        ruby_source : String,
        func_name : String,
        param_types : Array(Type),
        return_type : Type,
        compiler_flags : String = "-O3"
      ) : NativeFunction
        Spinel.compile_typed_function(ruby_source, func_name, param_types, return_type, compiler_flags)
      end
    end

    # Checks if the Spinel compiler binary is available
    def self.available? : Bool
      if path = ENV["SPINEL_PATH"]?
        return File.exists?(path)
      end
      res = begin
        Process.run("where", ["spinel"])
      rescue
        nil
      end
      res ? res.success? : false
    end

    # Returns the persistent cache directory for compiled Spinel libraries
    def self.cache_dir : String
      dir = ENV["RUBELLITE_SPINEL_CACHE_DIR"]? || File.join(Dir.current, ".rubellite_cache", "spinel")
      begin
        Dir.mkdir_p(dir)
      rescue
        dir = File.join(Dir.tempdir, "rubellite_spinel_cache")
        Dir.mkdir_p(dir)
      end
      dir
    end

    # Clears all cached Spinel shared libraries
    def self.clear_cache! : Nil
      dir = cache_dir
      if Dir.exists?(dir)
        Dir.children(dir).each do |file|
          next unless file.ends_with?(".dll") || file.ends_with?(".so") || file.ends_with?(".dylib") || file.ends_with?(".c")
          File.delete(File.join(dir, file)) rescue nil
        end
      end
    end

    # Locates the system C compiler (gcc, clang, or cl)
    def self.find_compiler : String
      Process.find_executable("gcc") || Process.find_executable("clang") || "gcc"
    end

    # Compiles raw C code into a multi-function Kernel container
    def self.compile_c(
      c_source : String,
      name : String = "kernel",
      compiler_flags : String = "-O3"
    ) : Kernel
      c_code = Transpiler.wrap_raw_c(c_source, name)
      lib_path, handle = compile_shared_lib(c_code, name, compiler_flags)
      Kernel.new(name, lib_path, handle, c_code)
    end

    # Compiles a single C function directly returning a NativeFunction
    def self.compile_c_function(
      c_source : String,
      func_name : String,
      return_type_name : String = "Int64",
      compiler_flags : String = "-O3"
    ) : NativeFunction
      kernel = compile_c(c_source, func_name, compiler_flags)
      kernel.function(func_name, return_type_name)
    end

    # Compiles a typed Ruby function into a NativeFunction using Type enums
    def self.compile_typed_function(
      ruby_source : String,
      func_name : String,
      param_types : Array(Type),
      return_type : Type,
      compiler_flags : String = "-O3"
    ) : NativeFunction
      param_c_types = param_types.map(&.to_c)
      ret_c_type = return_type.to_c

      c_code = Transpiler.transpile(ruby_source, func_name, [] of String, param_c_types, ret_c_type)
      lib_path, handle = compile_shared_lib(c_code, func_name, compiler_flags)

      fn_ptr = DynLink.sym(handle, func_name)
      raise "Failed to resolve exported Spinel symbol '#{func_name}'" if fn_ptr.null?

      NativeFunction.new(func_name, handle, fn_ptr, return_type.to_s)
    end

    # Compiles a Ruby function with Spinel into a NativeFunction with string type descriptors
    def self.compile_ruby(
      ruby_source : String,
      name : String,
      param_types : Array(String) = [] of String,
      return_type : String = "Int64",
      compiler_flags : String = "-O3"
    ) : NativeFunction
      c_arg_types = param_types.map { |t| Type.from_string(t).to_c }
      c_ret_type = Type.from_string(return_type).to_c

      c_code = Transpiler.transpile(ruby_source, name, [] of String, c_arg_types, c_ret_type)
      lib_path, handle = compile_shared_lib(c_code, name, compiler_flags)

      fn_ptr = DynLink.sym(handle, name)
      raise "Failed to resolve exported Spinel symbol '#{name}'" if fn_ptr.null?

      NativeFunction.new(name, handle, fn_ptr, return_type)
    end

    # Backwards-compatible compile_fn API accepting tuple types
    def self.compile_fn(
      ruby_code : String,
      name : String,
      args : Tuple,
      returns : Class
    ) : NativeFunction
      param_types = args.map { |t| t.to_s }.to_a
      return_type = returns.to_s
      compile_ruby(ruby_code, name, param_types, return_type)
    end

    # Compiles the given C source code to a shared library, utilizing content-addressable SHA256 caching
    private def self.compile_shared_lib(
      c_code : String,
      base_name : String,
      compiler_flags : String = "-O3"
    ) : Tuple(String, Void*)
      lib_ext = {% if flag?(:windows) %} "dll" {% elsif flag?(:darwin) %} "dylib" {% else %} "so" {% end %}
      target_env = {% if flag?(:windows) %} "win" {% elsif flag?(:darwin) %} "darwin" {% else %} "linux" {% end %}

      # Compute SHA256 hash for cache keying
      hash_input = "#{c_code}\nflags:#{compiler_flags}\ntarget:#{target_env}"
      hash = Digest::SHA256.hexdigest(hash_input)[0...16]

      cache_root = cache_dir
      cached_lib_path = File.join(cache_root, "#{base_name}_#{hash}.#{lib_ext}")

      # Check cache hit
      if File.exists?(cached_lib_path)
        handle = DynLink.open(cached_lib_path)
        return {cached_lib_path, handle} unless handle.null?
      end

      # Cache miss: compile to file
      c_path = File.join(cache_root, "#{base_name}_#{hash}.c")
      File.write(c_path, c_code)

      compiler = find_compiler
      args = ["-O3", "-shared"]
      {% unless flag?(:windows) %}
        args << "-fPIC"
      {% end %}
      args += ["-o", cached_lib_path, c_path]

      stdout = IO::Memory.new
      stderr = IO::Memory.new
      process = Process.run(compiler, args: args, output: stdout, error: stderr)

      unless process.success?
        err_msg = stderr.to_s.presence || stdout.to_s.presence || "Compiler process exited with code #{process.exit_code}"
        cmd_str = "#{compiler} #{args.join(' ')}"
        raise CompilationError.new(compiler, cmd_str, err_msg, c_code)
      end

      handle = DynLink.open(cached_lib_path)
      raise "Failed to load compiled Spinel library at #{cached_lib_path}" if handle.null?

      {cached_lib_path, handle}
    end
  end

  # Dynamic library loader wrapper
  module DynLink
    {% if flag?(:windows) %}
      lib LibWin32
        fun load_library = LoadLibraryA(name : UInt8*) : Void*
        fun get_proc_address = GetProcAddress(handle : Void*, name : UInt8*) : Void*
        fun free_library = FreeLibrary(handle : Void*) : Int32
      end

      def self.open(path : String) : Void*
        # Normalizing path for Windows LoadLibraryA
        normalized = path.gsub('/', '\\')
        LibWin32.load_library(normalized.to_unsafe)
      end

      def self.sym(handle : Void*, name : String) : Void*
        LibWin32.get_proc_address(handle, name.to_unsafe)
      end

      def self.close(handle : Void*) : Int32
        LibWin32.free_library(handle)
      end
    {% else %}
      lib LibDl
        fun dlopen(name : UInt8*, flags : Int32) : Void*
        fun dlsym(handle : Void*, name : UInt8*) : Void*
        fun dlclose(handle : Void*) : Int32
        RTLD_NOW = 2
      end

      def self.open(path : String) : Void*
        LibDl.dlopen(path.to_unsafe, LibDl::RTLD_NOW)
      end

      def self.sym(handle : Void*, name : String) : Void*
        LibDl.dlsym(handle, name.to_unsafe)
      end

      def self.close(handle : Void*) : Int32
        LibDl.dlclose(handle)
      end
    {% end %}
  end
end
