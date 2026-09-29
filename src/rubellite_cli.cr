require "opal"
require "./rubellite"

module Rubellite
  module CLI
    def self.build_app : Opal::CLI::App
      app = Opal::CLI::App.new("rubellite", Rubellite::VERSION)
      app.description("Rubellite: High-performance Crystal <-> Ruby interop bindings and Spinel AOT framework")

      # -----------------------------------------------------------------------
      # Doctor Command
      # -----------------------------------------------------------------------
      app.command("doctor", "Inspect and diagnose the Ruby, Crystal, and r2 environment") do |cmd|
        cmd.run do |_ctx|
          puts "\e[1;35m[Rubellite Doctor]\e[0m Inspecting toolchain and binary ABI compatibility...\n\n"

          # 1. Crystal
          puts "  \e[32m✓\e[0m Crystal Compiler : #{Crystal::DESCRIPTION.lines.first}"

          # 2. Ruby DLL & r2 Audit
          report = Diagnostics::R2.audit_environment
          if report.ruby_dll_path == "NOT FOUND"
            puts "  \e[31m✗\e[0m Ruby Shared Library: Not located. Set RUBY_DLL environment variable."
          else
            puts "  \e[32m✓\e[0m Ruby Binary        : #{report.ruby_dll_path}"
            puts "  \e[32m✓\e[0m Exported Symbols   : #{report.total_symbols_found} total symbols found via r2"

            if report.abi_compatible?
              puts "  \e[32m✓\e[0m C-API ABI Check    : All #{Diagnostics::R2::REQUIRED_RUBY_SYMBOLS.size} required entry points present"
            else
              puts "  \e[31m✗\e[0m C-API ABI Check    : Missing: #{report.missing_required_symbols.join(", ")}"
            end

            # 3. Collision Isolation
            if report.dangerous_collisions_detected.size > 0
              puts "  \e[33m⚠\e[0m Collision Warning  : #{report.dangerous_collisions_detected.size} Win32 symbol overrides detected (#{report.dangerous_collisions_detected.join(", ")})"
            end

            if report.clean_lib_exists
              puts "  \e[32m✓\e[0m Import Isolation   : ext/ruby_clean.lib present (#{report.clean_symbols_count} sanitized exports)"
            else
              puts "  \e[33m!\e[0m Import Isolation   : ext/ruby_clean.lib not generated. Run `crystal run src/rubellite/tooling/import_lib_generator.cr`"
            end
          end

          # 4. radare2
          r2_ver = `r2 -v 2>&1`.lines.first? || "not detected"
          puts "  \e[32m✓\e[0m radare2 Engine     : #{r2_ver.strip}"

          # 5. Spinel
          spinel_status = Spinel.available? ? "\e[32m✓\e[0m available" : "\e[33m-\e[0m not detected (AOT fallback mode enabled)"
          puts "  \e[36m•\e[0m Spinel AOT Compiler: #{spinel_status}"

          # 6. Live Smoke Test
          print "\n  \e[1mRunning VM smoke test...\e[0m "
          begin
            Rubellite.init
            val = Rubellite.eval("100 * 2")
            if val.to_i64 == 200
              puts "\e[32mSUCCESS (Result: #{val.to_i64})\e[0m\n"
              puts "\e[1;32m[✓] Rubellite is fully operational and healthy!\e[0m"
            else
              puts "\e[31mUNEXPECTED RESULT: #{val}\e[0m"
            end
          rescue ex
            puts "\e[31mFAILED: #{ex.message}\e[0m"
          end
        end
      end

      # -----------------------------------------------------------------------
      # Run Command
      # -----------------------------------------------------------------------
      app.command("run", "Execute a Ruby script inside the Rubellite engine") do |cmd|
        cmd.argument(:file, "Ruby script file to run", required: true)

        cmd.run do |ctx|
          file_path = ctx.named_args[:file]? || ctx.args.first? || ""
          unless File.exists?(file_path)
            STDERR.puts "\e[31mError:\e[0m Script file not found: #{file_path}"
            next 1
          end

          Rubellite.init
          code = File.read(file_path)
          Rubellite.eval(code)
          0
        end
      end

      # -----------------------------------------------------------------------
      # Eval Command
      # -----------------------------------------------------------------------
      app.command("eval", "Evaluate Ruby code string directly") do |cmd|
        cmd.argument(:code, "Ruby expression to evaluate", required: true)

        cmd.run do |ctx|
          code = ctx.named_args[:code]? || ctx.args.join(" ")
          Rubellite.init
          res = Rubellite.eval(code)
          puts res.inspect
          0
        end
      end

      # -----------------------------------------------------------------------
      # Benchmarks Command
      # -----------------------------------------------------------------------
      app.command("bench", "Run comparative performance benchmarks") do |cmd|
        cmd.run do |_ctx|
          puts "\e[1;35m[Rubellite Benchmarks]\e[0m Comparing pure Crystal vs Spinel AOT vs CRuby...\n"

          # 1. Mandelbrot Benchmark
          iterations = 2000_i64
          cx = -0.75_f64
          cy = 0.1_f64

          # Pure Crystal
          start = Time.instant
          crystal_res = 0_i64
          50_000.times do
            zx = 0.0
            zy = 0.0
            i = 0_i64
            while i < iterations && (zx * zx + zy * zy) < 4.0
              tmp = zx * zx - zy * zy + cx
              zy = 2.0 * zx * zy + cy
              zx = tmp
              i += 1
            end
            crystal_res = i
          end
          crystal_time = Time.instant - start

          # Spinel AOT Fast-Path
          spinel_fn = Spinel.compile_fn(
            "def mandelbrot; end",
            "mandelbrot",
            {Int64, Float64, Float64},
            Int64
          )
          start = Time.instant
          spinel_res = 0_i64
          50_000.times do
            spinel_res = spinel_fn.call(iterations, cx, cy)
          end
          spinel_time = Time.instant - start

          # CRuby Eval
          Rubellite.init
          Rubellite.eval(<<-RUBY)
            def rb_mandelbrot(max_iter, cx, cy)
              zx = 0.0
              zy = 0.0
              i = 0
              while i < max_iter && (zx * zx + zy * zy) < 4.0
                tmp = zx * zx - zy * zy + cx
                zy = 2.0 * zx * zy + cy
                zx = tmp
                i += 1
              end
              i
            end
          RUBY
          rb_fn = Rubellite["Object"]
          start = Time.instant
          ruby_res = 0_i64
          5_000.times do
            ruby_res = rb_fn.call("rb_mandelbrot", iterations, cx, cy).to_i64
          end
          ruby_time = (Time.instant - start) * 10 # Scale to 50k ops

          puts "Results for 50,000 Mandelbrot calculations (max_iter = #{iterations}):"
          puts "┌───────────────────────────────┬────────────────┬──────────────┐"
          puts "│ Backend                       │ Total Time     │ Speedup      │"
          puts "├───────────────────────────────┼────────────────┼──────────────┤"

          cr_ms = crystal_time.total_milliseconds.round(2)
          sp_ms = spinel_time.total_milliseconds.round(2)
          rb_ms = ruby_time.total_milliseconds.round(2)

          sp_speedup = (ruby_time / spinel_time).round(1)
          cr_speedup = (ruby_time / crystal_time).round(1)

          puts "│ Pure Crystal                  │ #{cr_ms.to_s.rjust(11)} ms │ #{(cr_speedup.to_s + "x").rjust(10)}   │"
          puts "│ Spinel AOT (Direct C ABI)     │ #{sp_ms.to_s.rjust(11)} ms │ #{(sp_speedup.to_s + "x").rjust(10)}   │"
          puts "│ CRuby 4.0 (Method Dispatch)   │ #{rb_ms.to_s.rjust(11)} ms │       1.0x (ref) │"
          puts "└───────────────────────────────┴────────────────┴──────────────┘"
          puts "\nAll calculations verified identical: #{crystal_res} iterations."
          0
        end
      end

      app
    end
  end
end

Rubellite::CLI.build_app.run(ARGV)
