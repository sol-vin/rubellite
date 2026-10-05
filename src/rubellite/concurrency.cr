require "./c_api"

module Rubellite
  module Concurrency
    # Runs a Crystal block with the Ruby Global VM Lock (GVL) released.
    # Allows other Ruby threads to run concurrently while this thread
    # performs blocking I/O, waiting on channels, or heavy computations.
    def self.without_gvl(&block : -> U) : U forall U
      captured = block
      ex_container = Pointer(Exception?).malloc(1)
      ex_container.value = nil

      {% if U <= NoReturn %}
        runner_data = {captured, ex_container}
        boxed_data = Box.box(runner_data)

        runner = ->(data : Void*) : Void* {
          blk, ex_ptr = Box(typeof(runner_data)).unbox(data)
          begin
            blk.call
          rescue ex
            ex_ptr.value = ex
          end
          Pointer(Void).null
        }

        LibRuby.rb_thread_call_without_gvl(
          runner,
          boxed_data.as(Void*),
          Pointer(Void).null,
          Pointer(Void).null
        )

        if err = ex_container.value
          raise err
        end
        raise "Unexpected return from NoReturn without_gvl block"
      {% else %}
        val_container = Pointer(U).malloc(1)
        runner_data = {captured, val_container, ex_container}
        boxed_data = Box.box(runner_data)

        runner = ->(data : Void*) : Void* {
          blk, v_ptr, ex_ptr = Box(typeof(runner_data)).unbox(data)
          begin
            v_ptr.value = blk.call
          rescue ex
            ex_ptr.value = ex
          end
          Pointer(Void).null
        }

        LibRuby.rb_thread_call_without_gvl(
          runner,
          boxed_data.as(Void*),
          Pointer(Void).null,
          Pointer(Void).null
        )

        if err = ex_container.value
          raise err
        end

        val_container.value
      {% end %}
    end

    # Runs a Crystal block while holding the Ruby GVL (from a thread that currently doesn't hold it).
    def self.with_gvl(&block : -> U) : U forall U
      captured = block
      ex_container = Pointer(Exception?).malloc(1)
      ex_container.value = nil

      {% if U <= NoReturn %}
        runner_data = {captured, ex_container}
        boxed_data = Box.box(runner_data)

        runner = ->(data : Void*) : Void* {
          blk, ex_ptr = Box(typeof(runner_data)).unbox(data)
          begin
            blk.call
          rescue ex
            ex_ptr.value = ex
          end
          Pointer(Void).null
        }

        LibRuby.rb_thread_call_with_gvl(
          runner,
          boxed_data.as(Void*)
        )

        if err = ex_container.value
          raise err
        end
        raise "Unexpected return from NoReturn with_gvl block"
      {% else %}
        val_container = Pointer(U).malloc(1)
        runner_data = {captured, val_container, ex_container}
        boxed_data = Box.box(runner_data)

        runner = ->(data : Void*) : Void* {
          blk, v_ptr, ex_ptr = Box(typeof(runner_data)).unbox(data)
          begin
            v_ptr.value = blk.call
          rescue ex
            ex_ptr.value = ex
          end
          Pointer(Void).null
        }

        LibRuby.rb_thread_call_with_gvl(
          runner,
          boxed_data.as(Void*)
        )

        if err = ex_container.value
          raise err
        end

        val_container.value
      {% end %}
    end
  end
end
