require "./c_api"

module Rubellite
  module Concurrency
    # Runs a Crystal block with the Ruby Global VM Lock (GVL) released.
    # Allows other Ruby threads to run concurrently while this thread
    # performs blocking I/O, waiting on channels, or heavy computations.
    def self.without_gvl(&block : -> U) : U forall U
      boxed = Box.box(block)
      runner = ->(data : Void*) : Void* {
        proc = Box(typeof(block)).unbox(data)
        res = proc.call
        # Box the result to return through pointer
        Box.box(res).as(Void*)
      }

      raw_result = LibRuby.rb_thread_call_without_gvl(
        runner,
        boxed.as(Void*),
        Pointer(Void).null,
        Pointer(Void).null
      )

      Box(U).unbox(raw_result)
    end

    # Runs a Crystal block while holding the Ruby GVL (from a thread that currently doesn't hold it).
    def self.with_gvl(&block : -> U) : U forall U
      boxed = Box.box(block)
      runner = ->(data : Void*) : Void* {
        proc = Box(typeof(block)).unbox(data)
        res = proc.call
        Box.box(res).as(Void*)
      }

      raw_result = LibRuby.rb_thread_call_with_gvl(
        runner,
        boxed.as(Void*)
      )

      Box(U).unbox(raw_result)
    end
  end
end
