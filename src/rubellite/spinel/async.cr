require "./channel"
require "../concurrency"

module Rubellite
  module Spinel
    # Raised when an asynchronous Future computation exceeds its timeout
    class TimeoutError < Exception
    end

    # Represents a pending or completed asynchronous native computation
    class Future(T)
      getter channel : Channel(Tuple(T?, Exception?))
      @result : T?
      @exception : Exception?
      @completed : Atomic(Int32)

      def initialize
        @channel = Channel(Tuple(T?, Exception?)).new(1)
        @completed = Atomic(Int32).new(0)
      end

      def complete(val : T) : Nil
        @result = val
        @completed.set(1)
        @channel.send({val, nil}) rescue nil
      end

      def fail(ex : Exception) : Nil
        @exception = ex
        @completed.set(1)
        @channel.send({nil, ex}) rescue nil
      end

      def completed? : Bool
        @completed.get == 1
      end

      def value? : T?
        @result
      end

      def exception? : Exception?
        @exception
      end

      # Awaits computation completion, returning the result or raising an exception
      def get : T
        if completed?
          if ex = @exception
            raise ex
          else
            return @result.not_nil!
          end
        end

        val, ex = @channel.receive
        if ex
          raise ex
        else
          val.not_nil!
        end
      end

      # Awaits computation completion with a timeout guard
      def get(timeout : Time::Span) : T
        if completed?
          if ex = @exception
            raise ex
          else
            return @result.not_nil!
          end
        end

        select
        when res = @channel.receive
          val, ex = res
          if ex
            raise ex
          else
            val.not_nil!
          end
        when timeout(timeout)
          raise TimeoutError.new("Spinel::Future timed out waiting for result after #{timeout}")
        end
      end
    end

    # Helper for boxing Crystal closures and producing C-ABI function pointers
    class CallbackBridge(R)
      getter boxed_proc : Void*

      def initialize(&block : Int64, Int64 -> R)
        @boxed_proc = Box(typeof(block)).box(block)
      end

      # Static trampoline for 2-argument callbacks (e.g. progress: current, total)
      def self.trampoline_2arg
        ->(ctx : Void*, arg1 : Int64, arg2 : Int64) : Nil {
          blk = Box(Proc(Int64, Int64, R)).unbox(ctx)
          blk.call(arg1, arg2)
          nil
        }
      end

      # Static trampoline for 1-argument callbacks (e.g. on_item: val)
      def self.trampoline_1arg
        ->(ctx : Void*, arg1 : Int64) : Nil {
          blk = Box(Proc(Int64, R)).unbox(ctx)
          blk.call(arg1)
          nil
        }
      end
    end
  end
end
