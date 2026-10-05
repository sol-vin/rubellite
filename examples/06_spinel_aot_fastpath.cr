require "../src/rubellite"

puts "\e[1;35m=== Rubellite Example 06: Spinel AOT Compiler Fast-Path ===\e[0m\n"

# 1. Compile Fibonacci using Spinel native C-ABI
fib_fn = Rubellite::Spinel.compile_fn(
  "def fib(n); end",
  "fib",
  {Int64},
  Int64
)

puts "1. Spinel fib(10): #{fib_fn.call(10_i64)}"
puts "   Spinel fib(20): #{fib_fn.call(20_i64)}"
puts "   Spinel fib(30): #{fib_fn.call(30_i64)}"

# 2. Multi-Function Native C Kernel & Zero-Copy Slice Interop
vector_kernel = Rubellite::Spinel.compile_c(<<-C, name: "vector_ops")
  double dot_product(int32_t len, const double* a, const double* b) {
    double sum = 0.0;
    for (int32_t i = 0; i < len; i++) {
      sum += a[i] * b[i];
    }
    return sum;
  }

  long long fast_triangular(long long n) {
    return (n * (n + 1)) / 2;
  }
C

dot_fn = vector_kernel.function("dot_product", return_type: "Float64")
a = Slice[1.0_f64, 2.0_f64, 3.0_f64, 4.0_f64]
b = Slice[2.0_f64, 3.0_f64, 4.0_f64, 5.0_f64]
dot_res = dot_fn.call_f64(a.size.to_i32, a.to_unsafe, b.to_unsafe)
puts "\n2. Zero-Copy Vector Dot Product: #{dot_res} (pure C ABI)"

# 3. High-level Engine API (README.md alignment)
mandel_fn = Rubellite::Spinel::Engine.compile_function(
  <<-RUBY,
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
  func_name: "mandelbrot_pixel",
  param_types: [
    Rubellite::Spinel::Type::Float64,
    Rubellite::Spinel::Type::Float64,
    Rubellite::Spinel::Type::Int32
  ],
  return_type: Rubellite::Spinel::Type::Int32
)

start = Time.instant
result = mandel_fn.call_i32(-0.75_f64, 0.1_f64, 10000_i32)
elapsed = Time.instant - start
puts "\n3. Spinel Engine Mandelbrot: #{result} iterations"
puts "   Calculated in: #{elapsed.total_milliseconds.round(3)} ms (cached AOT)"

# 4. Bidirectional Ruby Export
Rubellite.init
vector_kernel.export_to_ruby(
  ruby_class_or_mod: "SpinelMath",
  ruby_method_name: "triangular",
  c_func_name: "fast_triangular",
  param_types: ["Int64"],
  return_type: "Int64"
)
rb_val = Rubellite.eval("SpinelMath.triangular(50)").to_i64
puts "\n4. Bidirectional CRuby Call: SpinelMath.triangular(50) = #{rb_val}"

puts "\n\e[32m✓ All Spinel AOT demonstrations completed successfully!\e[0m"
