require "./spec_helper"

describe "Rubellite Channel Streaming & Pipeline Architecture" do
  it "streams 1,000 items through a Crystal -> Ruby -> Crystal pipeline" do
    in_chan = Channel(Int64).new(50)
    out_chan = Channel(Int64).new(50)

    Rubellite.export_channel("pipe_in", in_chan)
    Rubellite.export_channel("pipe_out", out_chan)

    # Spawn producer fiber
    spawn do
      1000.times do |i|
        in_chan.send(i.to_i64)
      end
      in_chan.close
    end

    # Spawn Ruby streaming worker
    spawn do
      Ruby.eval(<<-RUBY)
        pipe_in.each do |item|
          # Double item and forward
          pipe_out.send(item * 2)
        end
        pipe_out.close
      RUBY
    end

    # Consume and compute total in Crystal
    total = 0_i64
    count = 0
    while (val = out_chan.receive?)
      total += val
      count += 1
    end

    count.should eq(1000)
    expected_sum = (0_i64...1000_i64).sum * 2
    total.should eq(expected_sum)
  end

  it "supports Ruby Queue compatibility methods (push, pop, <<, enq, deq)" do
    q_chan = Channel(String).new(10)
    Rubellite.export_channel("work_queue", q_chan)

    Ruby.eval(<<-RUBY)
      work_queue.push("task_1")
      work_queue << "task_2"
      work_queue.enq("task_3")
    RUBY

    item1 = Ruby.eval("work_queue.pop").to_s
    item2 = Ruby.eval("work_queue.deq").to_s
    item3 = Ruby.eval("work_queue.shift").to_s

    item1.should eq("task_1")
    item2.should eq("task_2")
    item3.should eq("task_3")
  end

  it "performs unbuffered (capacity = 0) rendezvous ping-pong between fiber and Ruby" do
    ping_chan = Channel(Int32).new(0) # unbuffered
    pong_chan = Channel(Int32).new(0) # unbuffered

    Rubellite.export_channel("ping_q", ping_chan)
    Rubellite.export_channel("pong_q", pong_chan)

    # Ruby echo actor
    spawn do
      5.times do
        val = Ruby.eval("ping_q.receive").to_i32
        Ruby.eval("pong_q.send(#{val + 100})")
      end
    end

    5.times do |i|
      ping_chan.send(i)
      received = pong_chan.receive
      received.should eq(i + 100)
    end
  end

  it "streams binary buffers (Channel(Bytes)) with embedded null bytes without loss" do
    bin_in = Channel(Bytes).new(5)
    bin_out = Channel(Bytes).new(5)

    Rubellite.export_channel("bin_in", bin_in)
    Rubellite.export_channel("bin_out", bin_out)

    spawn do
      Ruby.eval(<<-RUBY)
        # Receive binary chunk, append binary header, and send back
        chunk = bin_in.receive
        bin_out.send([0, 255, 170].pack("C*") + chunk)
      RUBY
    end

    # Binary data with null bytes and high bytes
    original_data = Bytes[0x01, 0x00, 0x02, 0x00, 0xFE, 0xFF]
    bin_in.send(original_data)

    processed = bin_out.receive
    expected_header = Bytes[0x00, 0xFF, 0xAA]
    processed[0, 3].should eq(expected_header)
    processed[3, original_data.size].should eq(original_data)
  end

  it "coordinates fan-in from multiple Crystal producer fibers into a single Ruby consumer" do
    fan_chan = Channel(Int32).new(20)
    Rubellite.export_channel("fan_in_queue", fan_chan)

    # 4 producer fibers sending 25 items each (100 total)
    4.times do |p_id|
      spawn do
        25.times do |i|
          fan_chan.send(1)
        end
      end
    end

    Ruby.eval(<<-RUBY)
      $fan_sum = 0
      100.times do
        $fan_sum += fan_in_queue.receive
      end
    RUBY

    Ruby.eval("$fan_sum").to_i32.should eq(100)
  end

  it "safely terminates when closing a channel during active wait" do
    wait_chan = Channel(String).new(0)
    Rubellite.export_channel("closing_queue", wait_chan)
    result_chan = Channel(String).new(1)

    spawn do
      val = Ruby.eval("closing_queue.receive?")
      result_chan.send(val.ruby_nil? ? "received_nil_on_close" : val.to_s)
    end

    Fiber.yield
    wait_chan.close

    status = result_chan.receive
    status.should eq("received_nil_on_close")
  end
end
