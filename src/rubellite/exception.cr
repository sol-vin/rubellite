require "./c_api"

module Rubellite
  # Represents an exception raised inside the Ruby runtime.
  class Error < Exception
    getter ruby_class : String
    getter ruby_backtrace : Array(String)

    def initialize(@message : String, @ruby_class : String = "RuntimeError", @ruby_backtrace : Array(String) = [] of String)
      full_msg = String.build do |io|
        io << "[#{@ruby_class}] #{@message}"
        unless @ruby_backtrace.empty?
          io << "\nRuby Backtrace:\n"
          @ruby_backtrace.each do |frame|
            io << "  from " << frame << "\n"
          end
        end
      end
      super(full_msg)
    end

    # Extracts the active Ruby error info from `LibRuby.rb_errinfo`
    def self.from_ruby_errinfo : Error
      err = LibRuby.rb_errinfo
      if err == LibRuby::Qnil || err == 0_u64
        return Error.new("Unknown Ruby Exception", "RuntimeError")
      end

      # Class name
      c_name = LibRuby.rb_obj_classname(err)
      class_name = c_name ? String.new(c_name) : "RubyException"

      # Message
      msg_id = LibRuby.rb_intern("message")
      msg_val = LibRuby.rb_funcallv(err, msg_id, 0, Pointer(LibRuby::Value).null)
      msg_cstr = LibRuby.rb_string_value_cstr(pointerof(msg_val))
      message = msg_cstr ? String.new(msg_cstr) : "No message provided"

      # Backtrace
      bt_id = LibRuby.rb_intern("backtrace")
      bt_val = LibRuby.rb_funcallv(err, bt_id, 0, Pointer(LibRuby::Value).null)
      backtrace = [] of String
      if bt_val != LibRuby::Qnil && bt_val != 0_u64
        len_id = LibRuby.rb_intern("length")
        len_val = LibRuby.rb_funcallv(bt_val, len_id, 0, Pointer(LibRuby::Value).null)
        len = (len_val >> 1).to_i64
        len.times do |i|
          entry = LibRuby.rb_ary_entry(bt_val, i)
          if entry != LibRuby::Qnil
            entry_cstr = LibRuby.rb_string_value_cstr(pointerof(entry))
            backtrace << String.new(entry_cstr) if entry_cstr
          end
        end
      end

      # Clear error info so subsequent calls are clean
      LibRuby.rb_set_errinfo(LibRuby::Qnil)

      Error.new(message, class_name, backtrace)
    end
  end

  # Exception used to signal raising a specific native Ruby exception class from Crystal
  class RubyRaiseException < Exception
    getter ruby_class : String

    def initialize(@ruby_class : String, message : String)
      super(message)
    end
  end

  # Raises a Ruby exception of the specified class with a custom message.
  # When invoked from Crystal callbacks, this cleanly unwinds to the dispatcher boundary
  # where the native Ruby exception is raised in the Ruby VM.
  def self.raise_ruby(klass_name : String, message : String) : NoReturn
    raise RubyRaiseException.new(klass_name, message)
  end
end
