require "./spec_helper"

describe "Rubellite GVL Concurrency & Thread Isolation" do
  it "executes blocking computations outside GVL via Concurrency.without_gvl" do
    result = Rubellite::Concurrency.without_gvl do
      # Heavy pure-Crystal computation outside Ruby GVL
      fib = ->(n : Int64) : Int64 {
        a, b = 0_i64, 1_i64
        n.times { a, b = b, a + b }
        a
      }
      fib.call(50_i64)
    end

    result.should eq(12586269025_i64)
  end

  it "allows concurrent Ruby threads to make progress while GVL is released" do
    Ruby.eval(<<-RUBY)
      $bg_counter = 0
      $stop_bg = false
      $bg_thread = Thread.new do
        while !$stop_bg
          $bg_counter += 1
          sleep 0.001
        end
      end
    RUBY

    # Sleep in Crystal while GVL is released so Ruby thread can increment counter
    Rubellite::Concurrency.without_gvl do
      sleep 0.05.seconds
    end

    Ruby.eval("$stop_bg = true")
    Ruby.eval("$bg_thread.join(3)")

    counter = Ruby.eval("$bg_counter").to_i64
    counter.should be > 0_i64
  end

  it "propagates Crystal exceptions cleanly from within without_gvl blocks" do
    expect_raises(Exception, "intentional error in without_gvl") do
      Rubellite::Concurrency.without_gvl do
        raise "intentional error in without_gvl"
      end
    end

    # Verify Ruby runtime remains operational after caught exception
    Ruby.eval("1 + 1").to_i64.should eq(2_i64)
  end
end
