require "../src/rubellite"

puts "\e[1;35m=== Rubellite Example 04: Typed Proxies and Class Definition ===\e[0m\n"

# Define a strongly typed Crystal proxy for the Ruby class at top-level
class MathServiceProxy < Rubellite::Proxy
  ruby_target "RubyMathService"

  ruby_method add(a : Int64, b : Int64), returns: Int64
  ruby_method power(base : Int64, exp : Int64), returns: Int64
  ruby_method format_summary(title : String, value : Int64), returns: String
end

Rubellite.start do
  # Define a Ruby class with some methods
  Rubellite.eval(<<-'RUBY')
    class RubyMathService
      def add(a, b)
        a + b
      end

      def power(base, exp)
        base ** exp
      end

      def format_summary(title, value)
        "#{title}: #{value}"
      end
    end
  RUBY

  # Instantiate and call typed methods
  service = MathServiceProxy.new
  sum = service.add(50_i64, 75_i64)
  pow = service.power(2_i64, 10_i64)
  msg = service.format_summary("Total Score", sum)

  puts "Proxy add(50, 75)   : #{sum}"
  puts "Proxy power(2, 10)  : #{pow}"
  puts "Proxy format_summary: #{msg}"
end
