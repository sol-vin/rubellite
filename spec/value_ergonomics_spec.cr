require "./spec_helper"

describe "Rubellite::Value Ergonomics & Collections" do
  it "supports size, length, and empty? checks" do
    empty_arr = Ruby.eval("[]")
    empty_arr.size.should eq(0)
    empty_arr.length.should eq(0)
    empty_arr.empty?.should be_true

    items = Ruby.eval("[10, 20, 30, 40, 50]")
    items.size.should eq(5)
    items.empty?.should be_false

    hash = Ruby.eval("{ a: 1, b: 2 }")
    hash.size.should eq(2)
    hash.empty?.should be_false
  end

  it "inspects keys and values from Ruby hashes" do
    hash = Ruby.eval("{ name: 'Crystal', speed: 9000 }")
    hash.has_key?("name").should be_true
    hash.has_key?("nonexistent").should be_false

    keys = hash.keys.map(&.symbol_name)
    keys.should contain("name")
    keys.should contain("speed")

    vals = hash.values.map(&.as_crystal)
    vals.should contain("Crystal")
    vals.should contain(9000_i64)
  end

  it "supports safe nested navigation via dig" do
    nested = Ruby.eval(<<-RUBY)
      {
        user: {
          profile: {
            tags: ["crystal", "ruby", "llvm"],
            settings: { theme: "dark" }
          }
        }
      }
    RUBY

    nested.dig("user", "profile", "settings", "theme").try(&.to_s).should eq("dark")
    nested.dig("user", "profile", "tags", 0).try(&.to_s).should eq("crystal")
    nested.dig("user", "profile", "tags", 2).try(&.to_s).should eq("llvm")
    nested.dig("user", "nonexistent", "field").should be_nil
  end

  it "iterates with each and each_pair" do
    arr = Ruby.eval("[10, 20, 30]")
    collected = [] of Int64
    arr.each do |item|
      collected << item.to_i64
    end
    collected.should eq([10_i64, 20_i64, 30_i64])

    hash = Ruby.eval("{ alpha: 1, beta: 2 }")
    pairs = Hash(String, Int64).new
    hash.each_pair do |k, v|
      pairs[k.symbol_name] = v.to_i64
    end
    pairs.should eq({"alpha" => 1_i64, "beta" => 2_i64})
  end

  it "performs introspection via respond_to? and kind_of?" do
    str = Ruby.eval("'hello'")
    str.respond_to?("upcase").should be_true
    str.respond_to?("non_existent_method_xyz").should be_false
    str.kind_of?("String").should be_true
    str.ruby_is_a?("Object").should be_true
    str.kind_of?("Integer").should be_false
  end

  it "safely executes methods via call?" do
    str = Ruby.eval("'hello'")
    str.call?("upcase").try(&.to_s).should eq("HELLO")
    str.call?("invalid_method").should be_nil
  end

  it "unpacks typed collections using to_a(T) and to_h(K, V)" do
    raw_arr = Ruby.eval("[1, 2, 3, 4, 5]")
    int_arr = raw_arr.to_a(Int32)
    int_arr.should eq([1, 2, 3, 4, 5])
    int_arr.should be_a(Array(Int32))

    raw_hash = Ruby.eval("{ 'one' => 10, 'two' => 20 }")
    typed_hash = raw_hash.to_h(String, Int64)
    typed_hash.should eq({"one" => 10_i64, "two" => 20_i64})
    typed_hash.should be_a(Hash(String, Int64))
  end

  it "performs recursive deep unboxing with as_crystal_deep" do
    complex = Ruby.eval(<<-RUBY)
      {
        'scores' => [100, 200, 300],
        'meta' => { 'active' => true, 'ratio' => 1.5 }
      }
    RUBY

    deep = complex.as_crystal_deep
    deep.is_a?(Hash(String, Rubellite::DeepValue)).should be_true
    h = deep.as(Hash(String, Rubellite::DeepValue))
    h["scores"].as(Array(Rubellite::DeepValue)).should eq([100_i64, 200_i64, 300_i64])
    meta = h["meta"].as(Hash(String, Rubellite::DeepValue))
    meta["active"].should eq(true)
    meta["ratio"].should eq(1.5)
  end

  it "provides convenience scalar unboxing helpers" do
    Ruby.eval("42").as_i.should eq(42)
    Ruby.eval("10000000000").as_i64.should eq(10000000000_i64)
    Ruby.eval("3.14").as_f.should be_close(3.14, 0.001)
    Ruby.eval("'Crystal'").as_s.should eq("Crystal")
    Ruby.eval("true").as_bool.should be_true
    Ruby.eval("nil").as_nil.should be_nil
  end
end
