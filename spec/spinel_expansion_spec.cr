require "./spec_helper"

# Define a module using the spinel_module and spinel_c macro DSLs for testing
spinel_module MathAccelerated do
  spinel_c add_ints(a : Int64, b : Int64), returns: Int64, code: <<-C
    return a + b;
  C

  spinel_c fast_hypot(x : Float64, y : Float64), returns: Float64, code: <<-C
    return sqrt(x * x + y * y);
  C

  spinel_c is_even(n : Int64), returns: Bool, code: <<-C
    return (n % 2) == 0;
  C
end

describe "Rubellite::Spinel Expansion & DSL/UX" do
  before_all do
    Rubellite.init
  end

  describe "Type System & Engine API (README.md alignment)" do
    it "compiles function using Rubellite::Spinel::Engine with Type enum" do
      ruby_source = <<-RUBY
        def mandelbrot_pixel(cr, ci, max_iter)
          zr = 0.0
          zi = 0.0
          i = 0
          while i < max_iter
            zr2 = zr * zr
            zi2 = zi * zi
            if zr2 + zi2 > 4.0
              return i
            end
            zi = 2.0 * zr * zi + ci
            zr = zr2 - zi2 + cr
            i = i + 1
          end
          max_iter
        end
      RUBY

      fn = Rubellite::Spinel::Engine.compile_function(
        ruby_source,
        func_name: "mandelbrot_pixel",
        param_types: [
          Rubellite::Spinel::Type::Float64,
          Rubellite::Spinel::Type::Float64,
          Rubellite::Spinel::Type::Int32
        ],
        return_type: Rubellite::Spinel::Type::Int32
      )

      fn.should be_a(Rubellite::Spinel::NativeFunction)
      res = fn.call_i32(-0.75_f64, 0.1_f64, 1000_i32)
      res.should eq(10_i32)
    end

    it "supports various scalar return types (Float64, Int32, Bool)" do
      c_code = <<-C
        double calc_circle_area(double radius) {
          return 3.141592653589793 * radius * radius;
        }

        int32_t clamp_i32(int32_t val, int32_t min_v, int32_t max_v) {
          if (val < min_v) return min_v;
          if (val > max_v) return max_v;
          return val;
        }

        bool is_divisible(int64_t n, int64_t d) {
          if (d == 0) return false;
          return (n % d) == 0;
        }
      C

      kernel = Rubellite::Spinel.compile_c(c_code, name: "scalar_types_kernel")

      area_fn = kernel.function("calc_circle_area", return_type: "Float64")
      area = area_fn.call_f64(10.0_f64)
      area.should be_close(314.159265, 0.0001)

      clamp_fn = kernel.function("clamp_i32", return_type: "Int32")
      clamp_fn.call_i32(150_i32, 0_i32, 100_i32).should eq(100_i32)
      clamp_fn.call_i32(-50_i32, 0_i32, 100_i32).should eq(0_i32)
      clamp_fn.call_i32(42_i32, 0_i32, 100_i32).should eq(42_i32)

      div_fn = kernel.function("is_divisible", return_type: "Bool")
      div_fn.call_bool(100_i64, 10_i64).should eq(true)
      div_fn.call_bool(100_i64, 7_i64).should eq(false)
    end
  end

  describe "Multi-Function Kernel Container (docs_src alignment)" do
    it "compiles and dispatches multiple functions via Spinel.compile_c" do
      c_source = <<-C
        long long c_fib(long long n) {
          if (n <= 1) return n;
          long long a = 0, b = 1;
          for (long long i = 2; i <= n; i++) {
            long long c = a + b;
            a = b;
            b = c;
          }
          return b;
        }

        long long c_factorial(long long n) {
          if (n <= 1) return 1;
          long long res = 1;
          for (long long i = 2; i <= n; i++) {
            res *= i;
          }
          return res;
        }
      C

      kernel = Rubellite::Spinel.compile_c(c_source, name: "math_kernel")

      # Dynamic dispatch by name
      kernel.call("c_fib", 10_i64).should eq(55_i64)
      kernel.call("c_fib", 20_i64).should eq(6765_i64)
      kernel.call("c_factorial", 5_i64).should eq(120_i64)
      kernel.call("c_factorial", 10_i64).should eq(3628800_i64)
    end

    it "raises helpful error when calling non-existent symbol" do
      kernel = Rubellite::Spinel.compile_c("int64_t dummy(void) { return 1; }", name: "dummy_kernel")
      expect_raises(Exception, /Exported symbol 'missing_symbol' not found/) do
        kernel.call("missing_symbol")
      end
    end
  end

  describe "Zero-Copy Memory & Slice Buffer Interop" do
    it "processes Crystal Slice(Float64) arrays directly in C with zero copying" do
      c_code = <<-C
        double dot_product(int32_t len, const double* a, const double* b) {
          double sum = 0.0;
          for (int32_t i = 0; i < len; i++) {
            sum += a[i] * b[i];
          }
          return sum;
        }

        void vector_scale(int32_t len, double* vec, double factor) {
          for (int32_t i = 0; i < len; i++) {
            vec[i] *= factor;
          }
        }
      C

      kernel = Rubellite::Spinel.compile_c(c_code, name: "vector_ops")

      dot_fn = kernel.function("dot_product", return_type: "Float64")
      scale_fn = kernel.function("vector_scale", return_type: "Void")

      # 1. Dot product test
      a = Slice[1.0_f64, 2.0_f64, 3.0_f64, 4.0_f64]
      b = Slice[2.0_f64, 3.0_f64, 4.0_f64, 5.0_f64]
      # 1*2 + 2*3 + 3*4 + 4*5 = 2 + 6 + 12 + 20 = 40.0
      res = dot_fn.call_f64(a.size.to_i32, a.to_unsafe, b.to_unsafe)
      res.should be_close(40.0, 0.0001)

      # 2. In-place vector scaling test
      vec = Slice[10.0_f64, 20.0_f64, 30.0_f64]
      scale_fn.call_void(vec.size.to_i32, vec.to_unsafe, 2.5_f64)
      vec[0].should be_close(25.0, 0.0001)
      vec[1].should be_close(50.0, 0.0001)
      vec[2].should be_close(75.0, 0.0001)
    end
  end

  describe "Content-Addressable SHA-256 Compilation Caching" do
    it "instantaneously reuses cached shared library on identical source" do
      code = <<-C
        int64_t cached_power(int64_t base, int64_t exp) {
          int64_t res = 1;
          for (int64_t i = 0; i < exp; i++) res *= base;
          return res;
        }
      C

      # Initial compile (generates .dll/.so into cache)
      t0 = Time.instant
      k1 = Rubellite::Spinel.compile_c(code, name: "cache_bench")
      k1.call("cached_power", 2_i64, 10_i64).should eq(1024_i64)

      # Secondary compile: must hit SHA-256 cache
      t1 = Time.instant
      k2 = Rubellite::Spinel.compile_c(code, name: "cache_bench")
      duration = Time.instant - t1
      k2.call("cached_power", 3_i64, 4_i64).should eq(81_i64)

      # Cache hit should be sub-50ms (typically < 2ms)
      duration.total_milliseconds.should be < 50.0
    end

    it "exposes and manages the cache directory" do
      cache_path = Rubellite::Spinel.cache_dir
      Dir.exists?(cache_path).should be_true
    end
  end

  describe "Bidirectional CRuby Export" do
    it "exports a Spinel native kernel into CRuby and executes from Rubellite.eval" do
      c_source = <<-C
        long long fast_triangular(long long n) {
          return (n * (n + 1)) / 2;
        }
      C

      kernel = Rubellite::Spinel.compile_c(c_source, name: "ruby_bridge_test")
      kernel.export_to_ruby(
        ruby_class_or_mod: "NativeMath",
        ruby_method_name: "triangular",
        c_func_name: "fast_triangular",
        param_types: ["Int64"],
        return_type: "Int64"
      )

      # Execute from Ruby VM!
      result = Rubellite.eval("NativeMath.triangular(10)").to_i64
      result.should eq(55_i64)

      result2 = Rubellite.eval("NativeMath.triangular(100)").to_i64
      result2.should eq(5050_i64)
    end
  end

  describe "Compiler Diagnostic UX" do
    it "raises Spinel::CompilationError with source context on syntax errors" do
      broken_c = <<-C
        int64_t broken_function(int64_t x) {
          undeclared_variable_xyz = 123
          return x +
        }
      C

      expect_raises(Rubellite::Spinel::CompilationError) do
        Rubellite::Spinel.compile_c(broken_c, name: "broken_kernel")
      end
    end
  end

  describe "Crystal Macro DSL (spinel_c & spinel_module)" do
    it "executes methods defined via spinel_module and spinel_c" do
      # Int64 addition
      MathAccelerated.add_ints(1234_i64, 5678_i64).should eq(6912_i64)

      # Float64 hypotenuse
      h = MathAccelerated.fast_hypot(3.0_f64, 4.0_f64)
      h.should be_close(5.0, 0.0001)

      # Bool check
      MathAccelerated.is_even(42_i64).should be_true
      MathAccelerated.is_even(43_i64).should be_false
    end
  end

  describe "Transpiler (compile_ruby)" do
    it "transpiles Ruby control flow and arithmetic to native C" do
      ruby_code = <<-RUBY
        def collatz_steps(n)
          steps = 0
          while n > 1
            if n % 2 == 0
              n = n / 2
            else
              n = 3 * n + 1
            end
            steps += 1
          end
          steps
        end
      RUBY

      fn = Rubellite::Spinel.compile_ruby(
        ruby_code,
        name: "collatz_steps",
        param_types: ["Int64"],
        return_type: "Int64"
      )

      # Collatz sequence for 6: 6 -> 3 -> 10 -> 5 -> 16 -> 8 -> 4 -> 2 -> 1 (8 steps)
      fn.call(6_i64).should eq(8_i64)
      # Collatz sequence for 1: 0 steps
      fn.call(1_i64).should eq(0_i64)
    end
  end

  describe "Radare2 Machine Code Disassembly Inspection" do
    it "attempts disassembly inspection without crashing" do
      kernel = Rubellite::Spinel.compile_c("int64_t ping(void) { return 42; }", name: "ping_kernel")
      disasm = kernel.disassemble("ping")
      disasm.should be_a(String)
      disasm.empty?.should be_false
    end
  end
end
