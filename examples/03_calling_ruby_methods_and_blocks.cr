require "../src/rubellite"

puts "\e[1;35m=== Rubellite Example 03: Methods and Crystal Block Execution ===\e[0m\n"

Rubellite.start do
  # 1. Calling Ruby methods with multiple arguments
  text = Rubellite.eval("'antigravity coding framework'")
  reversed = text.call("split").call("reverse").call("join", " - ")
  puts "Method chaining: #{reversed.to_s}"

  # 2. Passing a compiled Crystal block to Ruby map
  numbers = Rubellite.eval("[1, 2, 3, 4, 5]")
  puts "Original Ruby Array: #{numbers.inspect}"

  squared = numbers.call_with_block("map") do |args|
    val = args.first.to_i64
    (val * val).to_ruby
  end
  puts "Squared with Crystal block: #{squared.inspect}"

  # 3. Filtering with select and a Crystal block
  odds = numbers.call_with_block("select") do |args|
    (args.first.to_i64 % 2 != 0).to_ruby
  end
  puts "Odds filtered with Crystal block: #{odds.inspect}"
end
