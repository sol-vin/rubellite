require "../src/rubellite"

puts "\e[1;35m=== Rubellite Example 01: Basic Script Evaluation ===\e[0m\n"

Rubellite.start do
  # Arithmetic
  result = Rubellite.eval("10 * (5 + 3)")
  puts "Arithmetic: 10 * (5 + 3) = #{result.to_i64} (#{result.class_name})"

  # String manipulation
  greeting = Rubellite.eval("'hello from ' + 'CRuby!'.upcase")
  puts "String: #{greeting.to_s}"

  # Math module
  sqrt = Rubellite["Math"].call("sqrt", 144.0)
  puts "Math.sqrt(144.0) = #{sqrt.to_f64}"

  # Array creation and manipulation
  evens = Rubellite.eval("[1, 2, 3, 4, 5, 6].select { |n| n % 2 == 0 }")
  puts "Even numbers: #{evens.inspect}"
end
