require "./spec_helper"

describe "Rubellite Advanced Interop Scenarios & Edge Cases" do
  it "catches and distinguishes custom Ruby exception hierarchies" do
    Ruby.eval(<<-RUBY)
      class PaymentError < StandardError; end
      class InsufficientFundsError < PaymentError
        attr_reader :shortage
        def initialize(msg, shortage)
          super(msg)
          @shortage = shortage
        end
      end
    RUBY

    caught_class = ""
    caught_msg = ""

    begin
      Ruby.eval("raise InsufficientFundsError.new('Account balance too low', 250)")
    rescue ex : Rubellite::Error
      caught_class = ex.ruby_class
      caught_msg = ex.message.not_nil!
    end

    caught_class.should eq("InsufficientFundsError")
    caught_msg.should contain("Account balance too low")
  end

  it "allows Ruby classes to inherit from Crystal-defined ClassBuilder classes" do
    builder = Rubellite::ClassBuilder.new("BaseEngine")
    builder.def_method("base_power") do |args|
      100_i64.to_ruby
    end

    Ruby.eval(<<-RUBY)
      class TurboEngine < BaseEngine
        def turbo_power
          base_power * 3
        end
      end
    RUBY

    turbo = Ruby.eval("TurboEngine.new")
    turbo.call("base_power").to_i64.should eq(100_i64)
    turbo.call("turbo_power").to_i64.should eq(300_i64)
  end

  it "preserves state mutations in captured Crystal closures invoked from Ruby" do
    counter = 0

    Rubellite.export("increment_counter") do |args|
      counter += args[0].to_i64.to_i32
      counter.to_ruby
    end

    Ruby.eval("5.times { Rubellite.increment_counter(10) }")

    counter.should eq(50)
  end

  it "handles Bignum values and large integer arithmetic (> 64 bits)" do
    # 2^100 is far beyond 64-bit integer range
    bignum_str = Ruby.eval("(2**100).to_s").to_s
    bignum_str.should eq("1267650600228229401496703205376")

    # Bignum multiplication
    doubled_str = Ruby.eval("(2**100 * 2).to_s").to_s
    doubled_str.should eq("2535301200456458802993406410752")
  end

  it "handles binary strings containing null bytes without truncation" do
    raw_bytes = Bytes[0x68, 0x65, 0x00, 0x6c, 0x6c, 0x00, 0x6f] # "he\0ll\0o"
    rb_val = raw_bytes.to_ruby

    rb_val.call("bytesize").to_i64.should eq(7_i64)

    # Convert back to Crystal slice
    extracted = rb_val.to_slice
    extracted.size.should eq(7)
    extracted.should eq(raw_bytes)
  end

  it "safely cleans up circular Ruby object graphs under explicit GC trigger" do
    Ruby.eval(<<-RUBY)
      class Node
        attr_accessor :ref
      end

      # Create 100 circular references
      100.times do
        a = Node.new
        b = Node.new
        a.ref = b
        b.ref = a
      end
    RUBY

    # Force Ruby GC
    Rubellite::GC.start_ruby_gc

    # Ensure VM is still completely responsive
    val = Ruby.eval("42 * 2").to_i64
    val.should eq(84_i64)
  end

  it "supports mixing Ruby modules into Crystal ClassBuilder classes" do
    builder = Rubellite::ClassBuilder.new("BaseAuditor")
    builder.def_method("base_metric") do |args|
      "crystal_metric".to_ruby
    end

    Ruby.eval(<<-RUBY)
      module Loggable
        def log_metric
          "logged: " + base_metric
        end
      end
      BaseAuditor.include(Loggable)
    RUBY

    auditor = Ruby.eval("BaseAuditor.new")
    auditor.call("log_metric").to_s.should eq("logged: crystal_metric")
  end

  it "unboxes deeply nested empty collections cleanly with as_crystal_deep" do
    empty_tree = Ruby.eval("{ 'empty_arr' => [], 'empty_hash' => {}, 'nested' => { 'inner' => [] } }")
    deep = empty_tree.as_crystal_deep
    deep.is_a?(Hash(String, Rubellite::DeepValue)).should be_true
    h = deep.as(Hash(String, Rubellite::DeepValue))
    h["empty_arr"].as(Array(Rubellite::DeepValue)).empty?.should be_true
    h["empty_hash"].as(Hash(String, Rubellite::DeepValue)).empty?.should be_true
  end

  it "converts large 10,000-element collections with typed unboxing" do
    Ruby.eval("$big_arr = (1..10000).to_a")
    big_arr = Ruby.eval("$big_arr")
    typed = big_arr.to_a(Int32)
    typed.size.should eq(10000)
    typed.first.should eq(1)
    typed.last.should eq(10000)
    typed.sum.to_i64.should eq(50005000_i64)
  end
end
