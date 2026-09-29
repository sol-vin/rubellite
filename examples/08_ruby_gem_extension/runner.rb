# Runner script showing Ruby loading and using the Crystal native extension
puts "Testing Ruby extension built from Crystal..."

begin
  require_relative 'fast_stats'
  puts "Successfully required fast_stats extension!"
rescue LoadError => e
  puts "Note: Compile the extension first: crystal build --cross-compile or --link-flags to generate .so / .dll"
end
