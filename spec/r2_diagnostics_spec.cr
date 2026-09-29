require "./spec_helper"

describe Rubellite::Diagnostics::R2 do
  it "audits the Ruby binary environment via radare2" do
    report = Rubellite::Diagnostics::R2.audit_environment

    report.ruby_dll_path.should_not eq("NOT FOUND")
    report.total_symbols_found.should be > 1000
    report.abi_compatible?.should be_true
    {% if flag?(:windows) %}
      report.clean_lib_exists.should be_true
      report.clean_symbols_count.should be > 2000
    {% end %}
  end

  it "disassembles Ruby exported functions" do
    report = Rubellite::Diagnostics::R2.audit_environment
    disasm = Rubellite::Diagnostics::R2.disassemble(report.ruby_dll_path, "rb_eval_string_protect", 5)

    disasm.should_not be_empty
  end
end
