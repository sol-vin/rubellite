require "./spec_helper"

describe "Rubellite Type Conversions" do
  it "converts Crystal primitives to Ruby values" do
    nil.to_ruby.ruby_nil?.should be_true
    true.to_ruby.true?.should be_true
    false.to_ruby.false?.should be_true
    42.to_ruby.to_i64.should eq(42_i64)
    3.14.to_ruby.to_f64.should be_close(3.14, 0.001)
    "crystal".to_ruby.to_s.should eq("crystal")
    :my_symbol.to_ruby.symbol_name.should eq("my_symbol")
  end

  it "converts Crystal collections to Ruby" do
    cr_ary = [1, 2, 3, 4]
    rb_ary = cr_ary.to_ruby
    rb_ary.array?.should be_true
    rb_ary.to_a.map(&.to_i64).should eq([1_i64, 2_i64, 3_i64, 4_i64])

    cr_hash = {"apple" => 10, "banana" => 20}
    rb_hash = cr_hash.to_ruby
    rb_hash.hash?.should be_true
    rb_hash["apple"].to_i64.should eq(10_i64)
    rb_hash["banana"].to_i64.should eq(20_i64)
  end

  it "converts Tuples and NamedTuples" do
    tup = {10, "hello", true}.to_ruby
    tup.array?.should be_true
    tup[0].to_i64.should eq(10_i64)
    tup[1].to_s.should eq("hello")
    tup[2].to_bool.should be_true

    ntup = {name: "Ian", age: 30}.to_ruby
    ntup.hash?.should be_true
    ntup["name"].to_s.should eq("Ian")
    ntup["age"].to_i64.should eq(30_i64)
  end

  it "unpacks Ruby values back to Crystal with as_crystal" do
    Rubellite.eval("nil").as_crystal.should be_nil
    Rubellite.eval("true").as_crystal.should eq(true)
    Rubellite.eval("false").as_crystal.should eq(false)
    Rubellite.eval("100").as_crystal.should eq(100_i64)
    Rubellite.eval("'testing'").as_crystal.should eq("testing")
  end
end
