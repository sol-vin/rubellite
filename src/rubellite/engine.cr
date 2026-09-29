require "./c_api"
require "./value"
require "./convert"
require "./exception"

module Rubellite
  # Manages the embedded CRuby runtime lifecycle, script evaluation,
  # library loading, and constant resolution.
  module Engine
    @@initialized = false
    @@lock = Mutex.new

    # Returns true if the Ruby VM has been initialized
    def self.initialized? : Bool
      @@initialized
    end

    # Initializes the Ruby VM. Safe to call multiple times (idempotent).
    def self.init : Nil
      return if @@initialized

      @@lock.synchronize do
        return if @@initialized

        # 1. Initialize Ruby stack boundary from the current stack frame
        stack_bottom = 0_u64
        LibRuby.ruby_init_stack(pointerof(stack_bottom))

        # 2. System initialization
        argc = 0
        argv = Pointer(Pointer(UInt8)).null
        LibRuby.ruby_sysinit(pointerof(argc), pointerof(argv))

        # 3. VM Boot & load paths
        LibRuby.ruby_init
        LibRuby.ruby_init_loadpath

        # 4. Set default script name in Ruby
        eval_internal("$0 = 'rubellite'")

        @@initialized = true
      end
    end

    # Gracefully cleans up and terminates the Ruby VM
    def self.cleanup : Nil
      return unless @@initialized

      @@lock.synchronize do
        return unless @@initialized
        LibRuby.ruby_cleanup(0)
        @@initialized = false
      end
    end

    # Evaluates a Ruby code snippet within the VM.
    # Raises `Rubellite::Error` if an exception occurs.
    def self.eval(code : String) : Value
      init unless @@initialized
      eval_internal(code)
    end

    # Requires a Ruby feature/gem. Returns true if loaded, false if already required.
    def self.require(feature : String) : Bool
      eval("require '#{feature}'").to_bool
    end

    # Loads a Ruby file path.
    def self.load(path : String) : Bool
      eval("load '#{path}'").to_bool
    end

    # Resolves a Ruby top-level constant (e.g. "Math", "JSON", "Net::HTTP")
    def self.[](const_name : String) : Value
      eval(const_name)
    end

    # Internal protected eval implementation
    private def self.eval_internal(code : String) : Value
      state = 0
      res = LibRuby.rb_eval_string_protect(code.to_unsafe, pointerof(state))
      if state != 0
        raise Error.from_ruby_errinfo
      end
      Value.new(res)
    end
  end

  # Delegates top-level module methods to Engine
  def self.init : Nil
    Engine.init
  end

  def self.cleanup : Nil
    Engine.cleanup
  end

  def self.initialized? : Bool
    Engine.initialized?
  end

  def self.start(&block)
    init
    begin
      yield
    ensure
      # Keep VM active for subsequent calls unless explicit cleanup
    end
  end

  def self.eval(code : String) : Value
    Engine.eval(code)
  end

  def self.require(feature : String) : Bool
    Engine.require(feature)
  end

  def self.load(path : String) : Bool
    Engine.load(path)
  end

  def self.[](const_name : String) : Value
    Engine[const_name]
  end
end
