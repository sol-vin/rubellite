require "./spec_helper"

describe "Rubellite Multi-Fiber Concurrency & Synchronization" do
  it "safely executes concurrent Ruby.eval across 20 spawned fibers" do
    done_chan = Channel(Int64).new(20)

    20.times do |i|
      fiber_i = i
      spawn do
        begin
          res = Ruby.eval("#{fiber_i} * 10 + 5").to_i64
          done_chan.send(res)
        rescue
          done_chan.send(-1_i64)
        end
      end
    end

    results = [] of Int64
    20.times do
      val = select
      when res = done_chan.receive
        res
      when timeout(10.seconds)
        fail("Timed out waiting for fiber eval")
      end
      results << val
    end

    results.size.should eq(20)
    expected = (0...20).map { |i| (i * 10 + 5).to_i64 }
    results.sort.should eq(expected.sort)
  end

  it "supports re-entrant evaluation from within Crystal callbacks without deadlocking" do
    # Register an exported function that itself invokes Ruby.eval
    Rubellite.export("nested_compute") do |args|
      n = args[0].to_i64
      # Re-entrant Ruby evaluation inside callback
      sub_result = Ruby.eval("#{n} * 2").to_i64
      (sub_result + 1).to_ruby
    end

    final_val = Ruby.eval("Rubellite.nested_compute(21)").to_i64
    final_val.should eq(43_i64)
  end

  it "coordinates worker pools across multiple fibers accessing Ruby state" do
    tasks = Channel(Int32).new(50)
    results = Channel(Int64).new(50)

    # Spawn 5 worker fibers
    5.times do
      spawn do
        loop do
          task = tasks.receive?
          break unless task
          begin
            # Workers invoke Ruby math
            computed = Ruby.eval("Math.sqrt(#{task * 100}).to_i").to_i64
            results.send(computed)
          rescue
            results.send(-1_i64)
          end
        end
      end
    end

    # Feed 20 tasks
    20.times { |i| tasks.send(i + 1) }
    tasks.close

    collected = [] of Int64
    20.times do
      val = select
      when res = results.receive
        res
      when timeout(10.seconds)
        fail("Timed out waiting for worker pool task")
      end
      collected << val
    end

    collected.size.should eq(20)
    collected.all?(&.>=(10)).should be_true
  end

  it "serializes concurrent mutations of Ruby globals without memory corruption" do
    Ruby.eval("$global_counter = 0")
    mutex = Mutex.new
    done = Channel(Nil).new(15)

    15.times do
      spawn do
        begin
          Ruby.synchronize do
            Ruby.eval("$global_counter += 1")
          end
        ensure
          done.send(nil)
        end
      end
    end

    15.times do
      select
      when done.receive
      when timeout(10.seconds)
        fail("Timed out waiting for global mutation fiber")
      end
    end

    final_count = Ruby.eval("$global_counter").to_i64
    final_count.should eq(15_i64)
  end

  it "maintains isolation when concurrent fibers encounter Ruby errors" do
    success_chan = Channel(Bool).new(10)

    # 5 fibers succeed, 5 fibers raise
    10.times do |i|
      fiber_i = i
      spawn do
        if fiber_i % 2 == 0
          val = Ruby.eval("#{fiber_i} + 10").to_i64
          success_chan.send(val == fiber_i + 10)
        else
          begin
            Ruby.eval("raise 'intentional fiber error #{fiber_i}'")
            success_chan.send(false)
          rescue ex : Rubellite::Error
            # Verifies exception is safely intercepted as Rubellite::Error without process crashing
            success_chan.send(true)
          rescue
            success_chan.send(false)
          end
        end
      end
    end

    all_ok = [] of Bool
    10.times do
      val = select
      when res = success_chan.receive
        res
      when timeout(10.seconds)
        fail("Timed out waiting for error isolation check")
      end
      all_ok << val
    end

    all_ok.all?(&.itself).should be_true
  end

  it "coordinates fiber-safe Channel select across multiple Ruby-exported channels" do
    chan_a = Channel(String).new(1)
    chan_b = Channel(String).new(1)

    Rubellite.export_channel("select_chan_a", chan_a)
    Rubellite.export_channel("select_chan_b", chan_b)

    spawn do
      Ruby.eval("select_chan_b.send('message_from_b')")
    end

    selected_idx, selected_val = Channel.select(
      chan_a.receive_select_action,
      chan_b.receive_select_action
    )

    selected_idx.should eq(1)
    selected_val.should eq("message_from_b")
  end

  it "concurrently parses JSON across 10 fibers via Ruby standard library" do
    Ruby.require("json")
    json_mod = Ruby["JSON"]
    results = Channel(String).new(10)

    10.times do |i|
      fiber_i = i
      spawn do
        begin
          raw_json = %({"worker": #{fiber_i}, "status": "active"})
          parsed = json_mod.call("parse", raw_json)
          status = parsed["status"].to_s
          results.send(status)
        rescue ex
          results.send("error: #{ex.message}")
        end
      end
    end

    10.times do
      msg = select
      when res = results.receive
        res
      when timeout(10.seconds)
        fail("Timed out waiting for JSON parse fiber")
      end
      msg.should eq("active")
    end
  end
end
