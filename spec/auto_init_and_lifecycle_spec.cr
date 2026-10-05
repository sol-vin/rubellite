require "./spec_helper"

describe "Rubellite Auto-Initialization & Lifecycle" do
  it "reports initialized status through Rubellite and Ruby alias" do
    Rubellite.initialized?.should be_true
    Ruby.initialized?.should be_true
  end

  it "evaluates expressions via the Ruby alias" do
    val = Ruby.eval("40 + 2")
    val.to_i64.should eq(42_i64)
  end

  it "resolves constants via the Ruby alias" do
    math = Ruby["Math"]
    math.should be_a(Rubellite::Value)
    math.call("cos", 0.0).to_f64.should eq(1.0)
  end

  it "safely returns nil for undefined constants via []?" do
    Ruby["DefinitelyNotARealConstantXYZ"]?.should be_nil
    Rubellite["NonExistentModuleABC"]?.should be_nil
  end

  it "automatically converts primitives and collections to Ruby values" do
    # Integers and Floats
    100.to_ruby.to_i64.should eq(100_i64)
    3.14.to_ruby.to_f64.should be_close(3.14, 0.001)

    # Strings and Symbols
    "gemstone".to_ruby.to_s.should eq("gemstone")
    :ruby_symbol.to_ruby.symbol_name.should eq("ruby_symbol")

    # Bytes / Slice(UInt8)
    bytes = Bytes[72, 101, 108, 108, 111] # "Hello"
    bytes.to_ruby.to_s.should eq("Hello")

    # Arrays and Sets
    [10, 20, 30].to_ruby.to_a.size.should eq(3)
    Set{1, 2, 3}.to_ruby.to_a.size.should eq(3)

    # Hashes and NamedTuples
    {"a" => 1, "b" => 2}.to_ruby["a"].to_i64.should eq(1_i64)
    {name: "Rubellite", stars: 5}.to_ruby["name"].to_s.should eq("Rubellite")
  end
end
