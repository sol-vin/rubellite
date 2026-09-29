require "./c_api"
require "./value"

module Rubellite
  # Coordinates garbage collection between Crystal's Boehm GC and Ruby's mark-sweep GC.
  module GC
    @@pinned_crystal_objects = Hash(UInt64, Box(Void*)).new
    @@pinned_mutex = Mutex.new

    # Pins a Crystal object so Boehm GC will not collect it while Ruby holds a reference.
    def self.pin(obj : Object) : UInt64
      boxed = Box.box(obj)
      addr = boxed.address
      id = addr.to_u64
      @@pinned_mutex.synchronize do
        @@pinned_crystal_objects[id] = Box.box(boxed)
      end
      id
    end

    # Unpins a Crystal object when Ruby's GC finalizes the wrapper.
    def self.unpin(id : UInt64) : Nil
      @@pinned_mutex.synchronize do
        @@pinned_crystal_objects.delete(id)
      end
    end

    # Explicitly triggers Ruby GC cycle
    def self.start_ruby_gc : Nil
      LibRuby.rb_gc_start
    end

    # Registers a Ruby VALUE address with the Ruby GC root set
    def self.register_address(val_ptr : LibRuby::Value*) : Nil
      LibRuby.rb_gc_register_address(val_ptr)
    end

    # Unregisters a Ruby VALUE address from the Ruby GC root set
    def self.unregister_address(val_ptr : LibRuby::Value*) : Nil
      LibRuby.rb_gc_unregister_address(val_ptr)
    end
  end
end
