require "./spec_helper"

Rubellite.eval(<<-'RUBY')
  class RubyCalculator
    def add(a, b)
      a + b
    end

    def greet(name)
      "Hello, #{name}!"
    end
  end
RUBY

class CalculatorProxy < Rubellite::Proxy
  ruby_target "RubyCalculator"

  ruby_method add(a : Int64, b : Int64), returns: Int64
  ruby_method greet(name : String), returns: String
end

describe "Rubellite Macros and Typed Proxies" do
  it "invokes typed methods through Proxy" do
    calc = CalculatorProxy.new
    calc.add(10_i64, 25_i64).should eq(35_i64)
    calc.greet("Ian").should eq("Hello, Ian!")
  end
end
