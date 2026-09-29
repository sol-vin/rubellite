require "cradare2"

module Rubellite
  module Tooling
    # Generates a sanitized import library (.lib) for CRuby on Windows,
    # stripping dangerous Win32 symbol overrides (such as `Sleep`)
    # that would otherwise hijack the host runtime's standard library.
    class ImportLibGenerator
      # List of dangerous symbols exported by Ruby's Win32 port
      # that collide with KERNEL32 / UCRT
      DANGEROUS_EXPORTS = Set{
        "Sleep", "close", "read", "write", "open", "unlink", "rename",
        "stat", "fstat", "lseek", "dup", "dup2", "pipe", "waitpid",
        "kill", "signal", "select", "socket", "accept", "bind",
        "connect", "listen", "recv", "send", "shutdown", "ioctl"
      }

      def self.find_ruby_dll : String
        if env_path = ENV["RUBY_DLL"]?
          return env_path if File.exists?(env_path)
        end

        # Query Ruby config across all OSes (Windows bindir, Linux/macOS libdir)
        output = `ruby -e "require 'rbconfig'; puts [File.join(RbConfig::CONFIG['bindir'], RbConfig::CONFIG['LIBRUBY_SO'] || ''), File.join(RbConfig::CONFIG['libdir'], RbConfig::CONFIG['LIBRUBY_SO'] || ''), File.join(RbConfig::CONFIG['libdir'], 'libruby.so'), File.join(RbConfig::CONFIG['libdir'], 'libruby.dylib')].find { |f| File.file?(f) }"`.strip
        if File.exists?(output)
          return output
        end

        # Fallback search in standard paths
        candidates = Dir.glob([
          "C:/Ruby*/bin/*ruby*.dll",
          "C:/Users/*/scoop/apps/ruby/current/bin/*ruby*.dll",
          "/usr/lib/*/*ruby*.so*",
          "/usr/lib/*ruby*.so*",
          "/usr/local/lib/*ruby*.dylib*"
        ])
        if candidates.empty?
          raise "Unable to locate Ruby shared library. Please set RUBY_DLL environment variable."
        end
        candidates.first
      end

      def self.generate(
        dll_path : String = find_ruby_dll,
        output_lib : String = File.expand_path("ext/ruby_clean.lib"),
        output_def : String = File.expand_path("ext/ruby_clean.def")
      ) : String
        puts "[Rubellite] Inspecting Ruby DLL: #{dll_path}"
        dll_name = File.basename(dll_path)

        # Extract exported symbols using r2, llvm-readobj, or dumpbin
        symbols = Set(String).new

        if Process.find_executable("r2")
          begin
            raw_exports = `r2 -q -c "iE" "#{dll_path}"`
            raw_exports.each_line do |line|
              line = line.strip
              next if line.empty? || line.starts_with?("WARN") || line.starts_with?("ERROR")
              parts = line.split
              next if parts.size < 6
              sym = parts.last
              if (sym.starts_with?("rb_") || sym.starts_with?("ruby_") || sym.starts_with?("Init_")) && !DANGEROUS_EXPORTS.includes?(sym)
                symbols << sym
              end
            end
          rescue
            # Fall through to llvm-readobj
          end
        end

        if symbols.empty?
          readobj = Process.find_executable("llvm-readobj") ||
                    (File.exists?("C:/Program Files/LLVM/bin/llvm-readobj.exe") ? "C:/Program Files/LLVM/bin/llvm-readobj.exe" : nil)
          if readobj
            raw_exports = `\"#{readobj}\" --coff-exports \"#{dll_path}\"`
            raw_exports.each_line do |line|
              if line.includes?("Name:")
                parts = line.split("Name:")
                if parts.size > 1
                  sym = parts[1].strip
                  sym = sym.sub(/^\.refptr\./, "")
                  if (sym.starts_with?("rb_") || sym.starts_with?("ruby_") || sym.starts_with?("Init_")) && !DANGEROUS_EXPORTS.includes?(sym)
                    symbols << sym
                  end
                end
              end
            end
          end
        end

        if symbols.empty? && Process.find_executable("dumpbin")
          raw_exports = `dumpbin /exports \"#{dll_path}\"`
          raw_exports.each_line do |line|
            parts = line.strip.split
            if parts.size >= 4
              sym = parts[3]
              if (sym.starts_with?("rb_") || sym.starts_with?("ruby_") || sym.starts_with?("Init_")) && !DANGEROUS_EXPORTS.includes?(sym)
                symbols << sym
              end
            end
          end
        end

        if symbols.empty?
          raise "No valid Ruby exported symbols found in #{dll_path}"
        end

        puts "[Rubellite] Extracted #{symbols.size} safe Ruby API symbols (filtered out #{DANGEROUS_EXPORTS.size} conflicting Win32 symbols)"

        # Write .def file
        File.open(output_def, "w") do |f|
          f.puts "EXPORTS"
          symbols.to_a.sort.each do |sym|
            f.puts "    #{sym}"
          end
        end

        # Run llvm-dlltool
        dlltool = Process.find_executable("llvm-dlltool") ||
                  (File.exists?("C:/Program Files/LLVM/bin/llvm-dlltool.exe") ? "C:/Program Files/LLVM/bin/llvm-dlltool.exe" : "llvm-dlltool")
        cmd = "\"#{dlltool}\" -m i386:x86-64 -d \"#{output_def}\" -l \"#{output_lib}\" -D \"#{dll_name}\""
        puts "[Rubellite] Running: #{cmd}"
        system(cmd) || raise "llvm-dlltool failed to create #{output_lib}"

        puts "[Rubellite] Successfully generated clean import library: #{output_lib}"
        output_lib
      end
    end
  end
end

if PROGRAM_NAME.includes?("import_lib_generator")
  Rubellite::Tooling::ImportLibGenerator.generate
end
