require "./spec_helper"

# Module using the spinel_generator macro DSL for streaming
spinel_module StreamingMath do
  spinel_generator count_squares(limit : Int64), yields: Int64, code: <<-C
    for (int64_t i = 1; i <= limit; i++) {
      spinel_send(i * i);
    }
  C

  spinel_generator float_harmonics(count : Int64), yields: Float64, code: <<-C
    for (int64_t i = 1; i <= count; i++) {
      spinel_send_f64(1.0 / (double)i);
    }
  C
end

describe "Rubellite::Spinel Channel & Concurrency Bindings" do
  before_all do
    Rubellite.init
  end

  describe "Real-Time Channel Streaming (C -> Crystal Channel(T))" do
    it "streams 100 generated items from C kernel into Crystal Channel(Int64)" do
      c_source = <<-C
        EXPORT void generate_stream(int64_t count, SpinelChannelContext* chan) {
          int64_t a = 0, b = 1;
          for (int64_t i = 0; i < count; i++) {
            chan->send_i64(chan->ctx, a);
            int64_t next_val = a + b;
            a = b;
            b = next_val;
          }
        }
      C

      kernel = Rubellite::Spinel.compile_c(c_source, name: "fib_stream_kernel")
      channel = kernel.stream(Int64, "generate_stream", 15_i64)

      results = [] of Int64
      while val = channel.receive?
        results << val
      end

      results.size.should eq(15)
      results[0].should eq(0_i64)
      results[1].should eq(1_i64)
      results[2].should eq(1_i64)
      results[3].should eq(2_i64)
      results[4].should eq(3_i64)
      results[5].should eq(5_i64)
      results[10].should eq(55_i64)
      results[14].should eq(377_i64)
    end

    it "streams floating-point values from C kernel into Crystal Channel(Float64)" do
      c_source = <<-C
        EXPORT void generate_floats(int64_t n, SpinelChannelContext* chan) {
          for (int64_t i = 1; i <= n; i++) {
            chan->send_f64(chan->ctx, (double)i * 0.5);
          }
        }
      C

      kernel = Rubellite::Spinel.compile_c(c_source, name: "float_stream_kernel")
      channel = kernel.stream(Float64, "generate_floats", 5_i64)

      floats = [] of Float64
      while val = channel.receive?
        floats << val
      end

      floats.size.should eq(5)
      floats[0].should be_close(0.5, 0.0001)
      floats[1].should be_close(1.0, 0.0001)
      floats[4].should be_close(2.5, 0.0001)
    end
  end

  describe "Crystal Callback Invocations from C Kernel" do
    it "invokes Crystal block from C on each iteration with progress reports" do
      c_source = <<-C
        typedef void (*progress_cb)(void* user_data, int64_t step, int64_t total);

        EXPORT void simulate_work(int64_t total_steps, void* user_data, progress_cb cb) {
          for (int64_t i = 1; i <= total_steps; i++) {
            if (cb) cb(user_data, i, total_steps);
          }
        }
      C

      kernel = Rubellite::Spinel.compile_c(c_source, name: "progress_kernel")

      steps_recorded = [] of Tuple(Int64, Int64)
      kernel.call_with_callback("simulate_work", 10_i64) do |step, total|
        steps_recorded << {step, total}
      end

      steps_recorded.size.should eq(10)
      steps_recorded.first.should eq({1_i64, 10_i64})
      steps_recorded.last.should eq({10_i64, 10_i64})
    end
  end

  describe "Asynchronous Non-Blocking Execution (Future & async)" do
    it "executes heavy C computations on background fibers without blocking" do
      c_source = <<-C
        long long heavy_fib(long long n) {
          if (n <= 1) return n;
          long long a = 0, b = 1;
          for (long long i = 2; i <= n; i++) {
            long long c = a + b;
            a = b;
            b = c;
          }
          return b;
        }
      C

      kernel = Rubellite::Spinel.compile_c(c_source, name: "async_kernel")

      # Launch 5 concurrent futures on background fibers
      futures = (1..5).map do |idx|
        n = 10_i64 * idx
        kernel.async(Int64, "heavy_fib", n)
      end

      # Await all futures
      results = futures.map(&.get)
      results[0].should eq(55_i64)    # fib(10)
      results[1].should eq(6765_i64)  # fib(20)
    end

    it "supports timeout guard on Future#get" do
      future = Rubellite::Spinel::Future(Int64).new
      expect_raises(Rubellite::Spinel::TimeoutError) do
        future.get(10.milliseconds)
      end
    end
  end

  describe "Bidirectional CSP Pipeline (Channel -> C Worker -> Channel)" do
    it "pipes input channel items through a C processing kernel to an output channel" do
      c_source = <<-C
        EXPORT void transform_pipeline(SpinelChannelContext* in_chan, SpinelChannelContext* out_chan) {
          bool has_more = true;
          while (has_more) {
            int64_t val = in_chan->recv_i64(in_chan->ctx, &has_more);
            if (has_more) {
              out_chan->send_i64(out_chan->ctx, val * 10);
            }
          }
        }
      C

      kernel = Rubellite::Spinel.compile_c(c_source, name: "pipe_kernel")

      in_channel = Channel(Int64).new(10)
      out_channel = kernel.pipe(in_channel, Int64, "transform_pipeline")

      # Producer fiber
      spawn do
        5.times { |i| in_channel.send(i.to_i64 + 1) }
        in_channel.close
      end

      # Consumer verification
      received = [] of Int64
      while item = out_channel.receive?
        received << item
      end

      received.should eq([10_i64, 20_i64, 30_i64, 40_i64, 50_i64])
    end
  end

  describe "Generator Macro DSL (spinel_generator)" do
    it "streams squares into Channel(Int64) using macro syntax" do
      stream = StreamingMath.count_squares(5_i64)
      items = [] of Int64
      while val = stream.receive?
        items << val
      end

      items.should eq([1_i64, 4_i64, 9_i64, 16_i64, 25_i64])
    end

    it "streams harmonic numbers into Channel(Float64) using macro syntax" do
      stream = StreamingMath.float_harmonics(4_i64)
      floats = [] of Float64
      while val = stream.receive?
        floats << val
      end

      floats.size.should eq(4)
      floats[0].should be_close(1.0, 0.0001)     # 1/1
      floats[1].should be_close(0.5, 0.0001)     # 1/2
      floats[2].should be_close(0.33333, 0.0001) # 1/3
      floats[3].should be_close(0.25, 0.0001)    # 1/4
    end
  end

  describe "Concurrent Multi-Fiber Channel Streaming" do
    it "safely receives streaming data from 5 concurrent worker fibers executing C kernels" do
      c_source = <<-C
        EXPORT void fiber_stream_worker(int64_t worker_id, int64_t count, SpinelChannelContext* chan) {
          for (int64_t i = 1; i <= count; i++) {
            chan->send_i64(chan->ctx, worker_id * 1000 + i);
          }
        }
      C

      kernel = Rubellite::Spinel.compile_c(c_source, name: "multi_fiber_kernel")
      channel = Channel(Int64).new(100)
      bridge = Rubellite::Spinel::ChannelBridge(Int64).new(channel)
      ctx = bridge.to_c_context

      # Spawn 5 concurrent fibers executing the C kernel
      done = Channel(Nil).new(5)
      5.times do |worker_id|
        spawn do
          fn_ptr = Rubellite::DynLink.sym(kernel.handle, "fiber_stream_worker")
          Proc(Int64, Int64, Pointer(Rubellite::Spinel::ChannelContext), Nil).new(
            fn_ptr, Pointer(Void).null
          ).call((worker_id + 1).to_i64, 20_i64, pointerof(ctx))
          done.send(nil)
        end
      end

      # Spawn closer fiber
      spawn do
        5.times { done.receive }
        bridge.close
      end

      # Receive all items
      items = [] of Int64
      while val = channel.receive?
        items << val
      end

      # 5 workers * 20 items = 100 items
      items.size.should eq(100)
      items.any?(&.>(5000)).should be_true
      items.any?(&.<(2000)).should be_true
    end
  end
end
