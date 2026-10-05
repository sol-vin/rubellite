require "./spec_helper"

describe "Rubellite Stress, GC & Edge Cases" do
  it "preserves UTF-8, multi-byte, and emoji strings flawlessly" do
    sample = "💎 Rubellite: 宝石 • 日本語 • αβγ • 🚀 Rocket! 123"
    ruby_str = sample.to_ruby
    ruby_str.to_s.should eq(sample)

    eval_str = Ruby.eval("'💎 Rubellite: ' + '宝石'").to_s
    eval_str.should eq("💎 Rubellite: 宝石")
  end

  it "handles large collections with thousands of elements" do
    large_arr = Array(Int64).new(5000) { |i| i.to_i64 }
    rb_arr = large_arr.to_ruby

    rb_arr.size.should eq(5000)
    # Sum using Ruby enumerable reduce
    sum = rb_arr.call("sum").to_i64
    expected_sum = (0_i64...5000_i64).sum
    sum.should eq(expected_sum)
  end

  it "processes deeply nested hashes without stack corruption" do
    deep = Ruby.eval(<<-RUBY)
      { l1: { l2: { l3: { l4: { l5: "deep_value" } } } } }
    RUBY

    deep.dig("l1", "l2", "l3", "l4", "l5").try(&.to_s).should eq("deep_value")
  end

  it "survives intensive GC pressure and explicit garbage collection" do
    # Allocate 10,000 Ruby objects across loops
    10.times do
      arr = (0..1000).to_a.to_ruby
      _ = arr.call("map") { |items| (items[0].to_i64 * 2).to_ruby }
    end

    # Explicitly trigger Ruby GC
    Rubellite::GC.start_ruby_gc

    # Verify runtime is still fully intact and responsive
    test_val = Ruby.eval("100 + 200")
    test_val.to_i64.should eq(300_i64)
  end

  it "bridges concurrent channel streaming under rapid fiber yields" do
    chan = Channel(Int32).new(10)

    spawn do
      10.times do |i|
        chan.send(i)
        Fiber.yield
      end
      chan.close
    end

    bridge = Rubellite::ChannelBridge(Int32).new(chan)
    results = [] of Int32

    while (val = bridge.receive_ruby)
      break if val.ruby_nil?
      results << val.to_i32
    end

    results.should eq((0..9).to_a)
  end

  it "catches and handles Ruby stack overflow errors gracefully" do
    Ruby.eval(<<-'RUBY')
      def infinite_recursion(n)
        infinite_recursion(n + 1)
      end
    RUBY

    expect_raises(Rubellite::Error) do
      Ruby.eval("infinite_recursion(1)")
    end
  end
end
