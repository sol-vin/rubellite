require "../src/rubellite"

puts "\e[1;35m=== Rubellite Example 02: Type Conversions & Collections ===\e[0m\n"

Rubellite.start do
  # 1. Convert Crystal Array & Hash to Ruby
  cr_array = [10, 20, 30, 40]
  rb_array = cr_array.to_ruby
  puts "Crystal Array -> Ruby: #{rb_array.inspect}"

  cr_hash = {"name" => "Ian", "lang" => "Crystal", "stars" => 999}
  rb_hash = cr_hash.to_ruby
  puts "Crystal Hash -> Ruby: #{rb_hash.inspect}"

  # 2. Access and modify Ruby hash from Crystal
  puts "Access [:name]: #{rb_hash["name"].to_s}"
  rb_hash["stars"] = 1000
  puts "Modified [:stars]: #{rb_hash["stars"].to_i64}"

  # 3. Unpack Ruby value to Crystal
  crystal_val = rb_hash["name"].as_crystal
  puts "Unpacked to Crystal String: #{crystal_val.class} => #{crystal_val}"
end
