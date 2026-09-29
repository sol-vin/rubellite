require "../src/rubellite"

puts "\e[1;35m=== Rubellite Example 07: radare2 Binary Forensics & Diagnostics ===\e[0m\n"

# 1. Audit the Ruby DLL / shared object
report = Rubellite::Diagnostics::R2.audit_environment

puts "Ruby Binary Path       : #{report.ruby_dll_path}"
puts "Total Exported Symbols : #{report.total_symbols_found}"
puts "ABI Check Status       : #{report.abi_compatible? ? "COMPATIBLE" : "INCOMPATIBLE"}"
puts "Sanitized Symbols Count: #{report.clean_symbols_count}"
puts "Win32 Hijack Immunity  : #{report.hijacked_symbols_isolated? ? "PROTECTED" : "EXPOSED"}"

# 2. Disassemble a Ruby C-API function
puts "\nDisassembly of rb_eval_string_protect:"
puts Rubellite::Diagnostics::R2.disassemble(report.ruby_dll_path, "rb_eval_string_protect", 6)
