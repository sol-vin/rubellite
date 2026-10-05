require "./c_api"
require "./value"
require "./concurrency"
require "./convert"
require "./gc"

module Rubellite
  # Abstract interface for channel bridges
  abstract class BaseChannelBridge
    abstract def send_ruby(val : Value) : Nil
    abstract def receive_ruby : Value
    abstract def close : Nil
    abstract def closed? : Bool
  end

  # Typed channel bridge connecting a Crystal Channel(T) with Ruby
  class ChannelBridge(T) < BaseChannelBridge
    getter channel : Channel(T)

    def initialize(@channel : Channel(T))
    end

    def self.new(capacity : Int32 = 0)
      new(Channel(T).new(capacity))
    end

    def send_ruby(val : Value) : Nil
      crystal_val = {% if T == Value %}
                      val
                    {% elsif T == String %}
                      val.to_s
                    {% elsif T == Int64 %}
                      val.to_i64
                    {% elsif T == Int32 %}
                      val.to_i32
                    {% elsif T == Float64 %}
                      val.to_f64
                    {% elsif T == Bool %}
                      val.to_bool
                    {% elsif T == Bytes %}
                      val.to_slice
                    {% else %}
                      val.as_crystal.as(T)
                    {% end %}

      Concurrency.without_gvl do
        @channel.send(crystal_val)
      end
    rescue Channel::ClosedError
      # Channel closed while sending
      nil
    end

    def receive_ruby : Value
      result = Concurrency.without_gvl do
        @channel.receive?
      end
      if result.nil?
        Value.new(LibRuby::Qnil)
      else
        result.to_ruby
      end
    end

    def close : Nil
      @channel.close
    end

    def closed? : Bool
      @channel.closed?
    end
  end

  # Registry of active channels accessible by Ruby scripts
  module ChannelRegistry
    @@channels = Hash(String, BaseChannelBridge).new
    @@channels_by_id = Hash(UInt64, BaseChannelBridge).new
    @@lock = Mutex.new
    @@setup_done = false

    def self.register(name : String, bridge : BaseChannelBridge) : Nil
      setup_ruby_channel_class unless @@setup_done
      id = bridge.object_id
      @@lock.synchronize do
        @@channels[name] = bridge
        @@channels_by_id[id] = bridge
      end

      # Expose as a global method in Ruby
      Engine.eval(<<-RUBY)
        def #{name}
          Crystal::Channel._from_id(#{id})
        end
      RUBY
    end

    def self.get_by_id(id : UInt64) : BaseChannelBridge?
      @@lock.synchronize do
        @@channels_by_id[id]?
      end
    end

    # Bootstraps the `Crystal::Channel` class in Ruby
    def self.setup_ruby_channel_class : Nil
      return if @@setup_done
      @@setup_done = true

      Engine.eval(<<-RUBY)
        module Crystal
          class Channel
            include Enumerable

            attr_reader :bridge_id

            def initialize(capacity = 0)
              @bridge_id = Channel._create_bridge(capacity)
            end

            def self._from_id(id)
              obj = allocate
              obj.instance_variable_set(:@bridge_id, id)
              obj
            end

            def send(val)
              Channel._bridge_send(@bridge_id, val)
              self
            end

            def receive
              Channel._bridge_receive(@bridge_id)
            end

            def receive?
              Channel._bridge_receive(@bridge_id)
            end

            # Ruby Queue compatibility aliases
            alias_method :push, :send
            alias_method :<<, :send
            alias_method :enq, :send
            alias_method :pop, :receive
            alias_method :deq, :receive
            alias_method :shift, :receive

            def close
              Channel._bridge_close(@bridge_id)
              self
            end

            def closed?
              Channel._bridge_closed(@bridge_id)
            end

            # Streams channel values until the channel is closed and drained
            def each
              return to_enum(:each) unless block_given?
              loop do
                val = receive?
                break if val.nil? && closed?
                yield val
              end
            end
          end
        end
      RUBY

      # Define singleton methods on Crystal::Channel in Ruby
      send_cb = ->(klass : LibRuby::Value, id_val : LibRuby::Value, item : LibRuby::Value) : LibRuby::Value {
        id = Value.new(id_val).to_i64.to_u64
        if bridge = ChannelRegistry.get_by_id(id)
          bridge.send_ruby(Value.new(item))
        end
        LibRuby::Qnil
      }

      recv_cb = ->(klass : LibRuby::Value, id_val : LibRuby::Value) : LibRuby::Value {
        id = Value.new(id_val).to_i64.to_u64
        if bridge = ChannelRegistry.get_by_id(id)
          bridge.receive_ruby.raw
        else
          LibRuby::Qnil
        end
      }

      close_cb = ->(klass : LibRuby::Value, id_val : LibRuby::Value) : LibRuby::Value {
        id = Value.new(id_val).to_i64.to_u64
        if bridge = ChannelRegistry.get_by_id(id)
          bridge.close
        end
        LibRuby::Qnil
      }

      closed_cb = ->(klass : LibRuby::Value, id_val : LibRuby::Value) : LibRuby::Value {
        id = Value.new(id_val).to_i64.to_u64
        if bridge = ChannelRegistry.get_by_id(id)
          bridge.closed? ? LibRuby::Qtrue : LibRuby::Qfalse
        else
          LibRuby::Qfalse
        end
      }

      chan_class = Engine.eval("Crystal::Channel").raw
      LibRuby.rb_define_singleton_method(chan_class, "_bridge_send".to_unsafe, send_cb.pointer, 2)
      LibRuby.rb_define_singleton_method(chan_class, "_bridge_receive".to_unsafe, recv_cb.pointer, 1)
      LibRuby.rb_define_singleton_method(chan_class, "_bridge_close".to_unsafe, close_cb.pointer, 1)
      LibRuby.rb_define_singleton_method(chan_class, "_bridge_closed".to_unsafe, closed_cb.pointer, 1)
    end
  end

  # Helper to export a Crystal channel to Ruby scripts
  def self.export_channel(name : String, channel : Channel(T)) : Nil forall T
    bridge = ChannelBridge(T).new(channel)
    ChannelRegistry.register(name, bridge)
  end
end
