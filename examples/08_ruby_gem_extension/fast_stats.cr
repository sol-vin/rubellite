require "../../src/rubellite"

# Example standalone C-extension compiled from Crystal for CRuby
ruby_extension "fast_stats" do |ext|
  ext.def_module "FastStats" do |mod|
    # Fast statistical algorithms compiled with Crystal LLVM
  end
end
