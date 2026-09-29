require "cradare2"
require "../tooling/import_lib_generator"

module Rubellite
  module Diagnostics
    # Diagnostic report produced by radare2 binary inspection
    class AuditReport
      property ruby_dll_path : String
      property total_symbols_found : Int32 = 0
      property required_symbols_present : Bool = true
      property missing_required_symbols : Array(String) = [] of String
      property dangerous_collisions_detected : Array(String) = [] of String
      property clean_lib_exists : Bool = false
      property clean_symbols_count : Int32 = 0

      def initialize(@ruby_dll_path : String)
      end

      def abi_compatible? : Bool
        @required_symbols_present && @missing_required_symbols.empty?
      end

      def hijacked_symbols_isolated? : Bool
        @clean_lib_exists
      end
    end

    # High-performance radare2 diagnostics driver for Rubellite
    module R2
      REQUIRED_RUBY_SYMBOLS = [
        "ruby_init",
        "ruby_init_stack",
        "ruby_sysinit",
        "ruby_init_loadpath",
        "rb_eval_string_protect",
        "rb_funcallv",
        "rb_intern",
        "rb_str_new",
        "rb_int2inum",
        "rb_thread_call_without_gvl"
      ]

      def self.find_r2_exe : String
        Process.find_executable("r2") ||
          [
            "/opt/homebrew/bin/r2",
            "/usr/local/bin/r2",
            "/usr/bin/r2",
            "C:/ProgramData/chocolatey/bin/r2.exe",
            "C:/tools/radare2/bin/r2.exe"
          ].find { |p| File.file?(p) } || "r2"
      end

      # Audits the target Ruby binary / DLL using radare2
      def self.audit_ruby_binary(path : String = Tooling::ImportLibGenerator.find_ruby_dll) : AuditReport
        report = AuditReport.new(path)
        r2_bin = find_r2_exe

        # Query exported symbols using r2
        raw_output = `\"#{r2_bin}\" -q -c "iE" \"#{path}\"`
        exported = Set(String).new

        raw_output.each_line do |line|
          line = line.strip
          next if line.empty? || line.starts_with?("WARN") || line.starts_with?("ERROR")
          parts = line.split
          next if parts.size < 6
          sym = parts.last
          exported << sym
          exported << sym.sub(/^_/, "")
        end

        if exported.empty?
          raw_output = `\"#{r2_bin}\" -q -c "is" \"#{path}\"`
          raw_output.each_line do |line|
            line = line.strip
            next if line.empty? || line.starts_with?("WARN") || line.starts_with?("ERROR")
            parts = line.split
            next if parts.size < 6
            sym = parts.last
            exported << sym
            exported << sym.sub(/^_/, "")
          end
        end

        report.total_symbols_found = exported.size
        return report if exported.empty?

        # Check required symbols
        REQUIRED_RUBY_SYMBOLS.each do |sym|
          unless exported.includes?(sym) || exported.includes?("_#{sym}")
            report.missing_required_symbols << sym
            report.required_symbols_present = false
          end
        end

        # Check dangerous collisions
        Tooling::ImportLibGenerator::DANGEROUS_EXPORTS.each do |danger|
          if exported.includes?(danger) || exported.includes?("_#{danger}")
            report.dangerous_collisions_detected << danger
          end
        end

        # Check clean import lib
        clean_lib_path = File.expand_path("ext/ruby_clean.lib")
        if File.exists?(clean_lib_path)
          report.clean_lib_exists = true
        end

        clean_def_path = File.expand_path("ext/ruby_clean.def")
        if File.exists?(clean_def_path)
          report.clean_symbols_count = File.read_lines(clean_def_path).size - 1
        end

        report
      end

      # Disassembles a given Ruby exported function using radare2
      def self.disassemble(path : String, symbol_name : String, instructions : Int32 = 10) : String
        r2_bin = find_r2_exe
        exports = `\"#{r2_bin}\" -q -c "iE~#{symbol_name}" \"#{path}\"`
        addr = ""
        exports.each_line do |line|
          parts = line.strip.split
          if parts.size >= 3 && (parts.last == symbol_name || parts.last == "_#{symbol_name}")
            addr = parts[1]
            break
          end
        end

        if addr.empty?
          exports = `\"#{r2_bin}\" -q -c "is~#{symbol_name}" \"#{path}\"`
          exports.each_line do |line|
            parts = line.strip.split
            if parts.size >= 3 && (parts.last == symbol_name || parts.last == "_#{symbol_name}")
              addr = parts[1]
              break
            end
          end
        end

        return "Symbol #{symbol_name} not found in exports" if addr.empty?

        cmd = "\"#{r2_bin}\" -q -c \"s #{addr}; pd #{instructions}\" \"#{path}\""
        `#{cmd}`
      end

      def self.audit_environment : AuditReport
        dll = begin
          Tooling::ImportLibGenerator.find_ruby_dll
        rescue
          "unknown"
        end
        if File.exists?(dll)
          audit_ruby_binary(dll)
        else
          AuditReport.new("NOT FOUND")
        end
      end
    end
  end
end
