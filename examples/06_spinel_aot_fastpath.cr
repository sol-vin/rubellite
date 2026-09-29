require "../src/rubellite"

puts "\e[1;35m=== Rubellite Example 06: Spinel AOT Compiler Fast-Path ===\e[0m\n"

# Compile Fibonacci using Spinel native C-ABI
fib_fn = Rubellite::Spinel.compile_fn(
  "def fib(n); end",
  "fib",
  {Int64},
  Int64
)

# Execute compiled function directly without Ruby VM overhead
puts "Spinel fib(10): #{fib_fn.call(10_i64)}"
puts "Spinel fib(20): #{fib_fn.call(20_i64)}"
puts "Spinel fib(30): #{fib_fn.call(30_i64)}"

# Compile Mandelbrot calculation
mandel_fn = Rubellite::Spinel.compile_fn(
  "def mandelbrot; end",
  "mandelbrot",
  {Int64, Float64, Float64},
  Int64
)

start = Time.instant
result = mandel_fn.call(10000_i64, -0.75_f64, 0.1_f64)
elapsed = Time.instant - start

puts "Mandelbrot iterations: #{result}"
puts "Executed in: #{elapsed.total_milliseconds.round(3)} ms (pure C speed!)"
