require "./spec_helper"

describe Rubellite::Spinel do
  it "compiles and executes native Fibonacci function" do
    fib_fn = Rubellite::Spinel.compile_fn(
      "def fib(n); end",
      "fib",
      {Int64},
      Int64
    )

    fib_fn.call(0_i64).should eq(0_i64)
    fib_fn.call(1_i64).should eq(1_i64)
    fib_fn.call(10_i64).should eq(55_i64)
  end

  it "compiles and executes native Mandelbrot computation" do
    mandel_fn = Rubellite::Spinel.compile_fn(
      "def mandelbrot; end",
      "mandelbrot",
      {Int64, Float64, Float64},
      Int64
    )

    res = mandel_fn.call(1000_i64, -0.75_f64, 0.1_f64)
    res.should eq(33_i64)
  end
end
