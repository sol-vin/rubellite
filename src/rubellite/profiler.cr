require "./engine"
require "./value"
require "./spinel"
require "./diagnostics/r2"

module Rubellite
  # Profiling, telemetry, and bytecode/assembly disassembly comparing CRuby YARV
  # VM execution against Spinel native compiled kernels.
  module Profiler
    # Benchmark result summary comparing YARV bytecode execution vs. Spinel native execution
    struct ProfileReport
      getter ruby_time : Time::Span
      getter spinel_time : Time::Span
      getter iterations : Int32
      getter speedup : Float64

      def initialize(@ruby_time : Time::Span, @spinel_time : Time::Span, @iterations : Int32)
        r_ms = @ruby_time.total_milliseconds
        s_ms = @spinel_time.total_milliseconds
        @speedup = s_ms > 0.0 ? (r_ms / s_ms) : 1.0
      end

      def to_s(io : IO) : Nil
        io.puts "=========================================================="
        io.puts "              RUBELLITE PROFILER REPORT                   "
        io.puts "=========================================================="
        io.printf "Iterations:     %-12d\n", @iterations
        io.printf "Ruby (YARV):    %-10.3f ms\n", @ruby_time.total_milliseconds
        io.printf "Spinel (Native):%-10.3f ms\n", @spinel_time.total_milliseconds
        io.printf "Speedup Factor: %-10.2fx\n", @speedup
        io.puts "=========================================================="
      end

      def inspect(io : IO) : Nil
        to_s(io)
      end
    end

    # Disassembles a Ruby code string into CRuby YARV bytecode instruction sequences
    def self.disasm_ruby(ruby_code : String) : String
      Rubellite.ensure_init!
      escaped = ruby_code.gsub('\\', "\\\\").gsub('"', "\\\"").gsub('\n', "\\n")
      cmd = "RubyVM::InstructionSequence.compile(\"#{escaped}\").disasm"
      Rubellite.eval(cmd).to_s
    end

    # Compares execution timing between a Ruby block/expression and a Spinel/Crystal action
    def self.compare(iterations : Int32, ruby_action : -> Nil, spinel_action : -> Nil) : ProfileReport
      # Warmup phase (up to 50 iterations)
      warmup = (iterations // 20).clamp(1, 50)
      warmup.times do
        ruby_action.call
        spinel_action.call
      end

      # Measure Ruby YARV execution
      t0 = Time.instant
      iterations.times { ruby_action.call }
      ruby_span = Time.instant - t0

      # Measure Spinel / native execution
      t1 = Time.instant
      iterations.times { spinel_action.call }
      spinel_span = Time.instant - t1

      ProfileReport.new(ruby_span, spinel_span, iterations)
    end

    # Profiles a Ruby eval expression against a compiled Spinel/Crystal proc
    def self.profile_eval(ruby_code : String, spinel_proc : -> Nil, iterations : Int32 = 1000) : ProfileReport
      Rubellite.ensure_init!
      ruby_action = ->{
        Rubellite.eval(ruby_code)
        nil
      }
      compare(iterations, ruby_action, spinel_proc)
    end
  end
end
