require "./spec_helper"

describe "Rubellite Channel and Concurrency Interop" do
  it "bridges Crystal Channel with Ruby scripts" do
    cr_chan = Channel(String).new(5)
    Rubellite.export_channel("test_queue", cr_chan)

    # Ruby sending to Crystal channel
    Rubellite.eval(<<-RUBY)
      test_queue.send("hello from ruby")
      test_queue.send("second message")
    RUBY

    msg1 = cr_chan.receive
    msg2 = cr_chan.receive

    msg1.should eq("hello from ruby")
    msg2.should eq("second message")
  end

  it "allows Ruby to receive from Crystal channel" do
    cr_chan = Channel(Int64).new(5)
    Rubellite.export_channel("int_queue", cr_chan)

    cr_chan.send(42_i64)
    cr_chan.send(99_i64)

    val1 = Rubellite.eval("int_queue.receive").to_i64
    val2 = Rubellite.eval("int_queue.receive").to_i64

    val1.should eq(42_i64)
    val2.should eq(99_i64)
  end

  it "coordinates closing state" do
    cr_chan = Channel(String).new(1)
    Rubellite.export_channel("closable_queue", cr_chan)

    Rubellite.eval("closable_queue.closed?").to_bool.should be_false
    cr_chan.close
    Rubellite.eval("closable_queue.closed?").to_bool.should be_true
  end
end
