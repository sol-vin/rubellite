module Rubellite
  module Spinel
    # C-ABI compatible struct representing channel communication callbacks
    @[Extern]
    struct ChannelContext
      property ctx : Void*
      property send_i64 : (Void*, Int64 -> Nil)
      property send_f64 : (Void*, Float64 -> Nil)
      property send_bool : (Void*, Bool -> Nil)
      property close : (Void* -> Nil)
      property recv_i64 : (Void*, Pointer(Bool) -> Int64)
      property recv_f64 : (Void*, Pointer(Bool) -> Float64)

      def initialize(
        @ctx : Void*,
        @send_i64 : (Void*, Int64 -> Nil),
        @send_f64 : (Void*, Float64 -> Nil),
        @send_bool : (Void*, Bool -> Nil),
        @close : (Void* -> Nil),
        @recv_i64 : (Void*, Pointer(Bool) -> Int64),
        @recv_f64 : (Void*, Pointer(Bool) -> Float64)
      )
      end
    end

    # Abstract interface for Spinel channel bridges
    abstract class BaseChannelBridge
      abstract def send_i64(val : Int64) : Nil
      abstract def send_f64(val : Float64) : Nil
      abstract def send_bool(val : Bool) : Nil
      abstract def recv_i64? : Int64?
      abstract def recv_f64? : Float64?
      abstract def close : Nil
      abstract def closed? : Bool
    end

    # Static C-ABI trampoline callbacks for channel communication
    module Trampolines
      @@send_i64_fn = ->(ctx : Void*, val : Int64) : Nil {
        bridge = Box(BaseChannelBridge).unbox(ctx)
        bridge.send_i64(val)
      }

      @@send_f64_fn = ->(ctx : Void*, val : Float64) : Nil {
        bridge = Box(BaseChannelBridge).unbox(ctx)
        bridge.send_f64(val)
      }

      @@send_bool_fn = ->(ctx : Void*, val : Bool) : Nil {
        bridge = Box(BaseChannelBridge).unbox(ctx)
        bridge.send_bool(val)
      }

      @@close_fn = ->(ctx : Void*) : Nil {
        bridge = Box(BaseChannelBridge).unbox(ctx)
        bridge.close
      }

      @@recv_i64_fn = ->(ctx : Void*, has_more : Pointer(Bool)) : Int64 {
        bridge = Box(BaseChannelBridge).unbox(ctx)
        if item = bridge.recv_i64?
          has_more.value = true
          item
        else
          has_more.value = false
          0_i64
        end
      }

      @@recv_f64_fn = ->(ctx : Void*, has_more : Pointer(Bool)) : Float64 {
        bridge = Box(BaseChannelBridge).unbox(ctx)
        if item = bridge.recv_f64?
          has_more.value = true
          item
        else
          has_more.value = false
          0.0_f64
        end
      }

      def self.send_i64_fn
        @@send_i64_fn
      end

      def self.send_f64_fn
        @@send_f64_fn
      end

      def self.send_bool_fn
        @@send_bool_fn
      end

      def self.close_fn
        @@close_fn
      end

      def self.recv_i64_fn
        @@recv_i64_fn
      end

      def self.recv_f64_fn
        @@recv_f64_fn
      end
    end

    # Thread-safe bidirectional channel bridge connecting Crystal's Channel(T) with native C
    class ChannelBridge(T) < BaseChannelBridge
      getter channel : Channel(T)
      getter lock : Mutex

      def initialize(@channel : Channel(T))
        @lock = Mutex.new
      end

      def self.new(capacity : Int32 = 64)
        new(Channel(T).new(capacity))
      end

      def send(val : T) : Nil
        @lock.synchronize do
          @channel.send(val) unless @channel.closed?
        end
      rescue Channel::ClosedError
        nil
      end

      def receive? : T?
        @lock.synchronize do
          @channel.receive?
        end
      end

      def close : Nil
        @lock.synchronize do
          @channel.close unless @channel.closed?
        end
      end

      def closed? : Bool
        @channel.closed?
      end

      def send_i64(val : Int64) : Nil
        {% if T == Int64 %}
          send(val)
        {% elsif T == Int32 %}
          send(val.to_i32)
        {% elsif T == Float64 %}
          send(val.to_f64)
        {% elsif T == Bool %}
          send(val != 0_i64)
        {% end %}
      end

      def send_f64(val : Float64) : Nil
        {% if T == Float64 %}
          send(val)
        {% elsif T == Float32 %}
          send(val.to_f32)
        {% elsif T == Int64 %}
          send(val.to_i64)
        {% end %}
      end

      def send_bool(val : Bool) : Nil
        {% if T == Bool %}
          send(val)
        {% end %}
      end

      def recv_i64? : Int64?
        if item = receive?
          {% if T == Int64 %}
            item
          {% elsif T == Int32 %}
            item.to_i64
          {% else %}
            nil
          {% end %}
        else
          nil
        end
      end

      def recv_f64? : Float64?
        if item = receive?
          {% if T == Float64 %}
            item
          {% elsif T == Float32 %}
            item.to_f64
          {% else %}
            nil
          {% end %}
        else
          nil
        end
      end

      # Creates a C-ABI context struct with function pointers referencing this bridge
      def to_c_context : ChannelContext
        boxed = Box(BaseChannelBridge).box(self)
        ChannelContext.new(
          ctx: boxed,
          send_i64: Trampolines.send_i64_fn,
          send_f64: Trampolines.send_f64_fn,
          send_bool: Trampolines.send_bool_fn,
          close: Trampolines.close_fn,
          recv_i64: Trampolines.recv_i64_fn,
          recv_f64: Trampolines.recv_f64_fn
        )
      end
    end
  end
end
