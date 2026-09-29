require "./spec_helper"

describe Rubellite::Value do
  it "detects nils" do
    val = Rubellite.eval("nil")
    val.ruby_nil?.should be_true
    val.to_bool.should be_false
    val.class_name.should eq("NilClass")
    val.to_s.should eq("")
  end

  it "detects booleans" do
    t = Rubellite.eval("true")
    f = Rubellite.eval("false")

    t.true?.should be_true
    t.bool?.should be_true
    t.to_bool.should be_true

    f.false?.should be_true
    f.bool?.should be_true
    f.to_bool.should be_false
  end

  it "detects and unboxes fixnums" do
    num = Rubellite.eval("42")
    num.fixnum?.should be_true
    num.to_i64.should eq(42_i64)
    num.to_i32.should eq(42_i32)
    num.class_name.should eq("Integer")
  end

  it "detects and unboxes flonums / floats" do
    fl = Rubellite.eval("2.71828")
    fl.numeric?.should be_true
    fl.to_f64.should be_close(2.71828, 0.0001)
  end

  it "handles strings and symbols" do
    str = Rubellite.eval("'ruby string'")
    str.string?.should be_true
    str.to_s.should eq("ruby string")

    sym = Rubellite.eval(":ruby_sym")
    sym.symbol?.should be_true
    sym.symbol_name.should eq("ruby_sym")
  end

  it "handles array operations" do
    ary = Rubellite.eval("[10, 20, 30]")
    ary.array?.should be_true
    ary.call("length").to_i64.should eq(3_i64)
    ary[0].to_i64.should eq(10_i64)
    ary[1].to_i64.should eq(20_i64)
    ary[2].to_i64.should eq(30_i64)

    list = ary.to_a
    list.size.should eq(3)
    list.map(&.to_i64).should eq([10_i64, 20_i64, 30_i64])
  end

  it "handles hash operations" do
    h = Rubellite.eval("{ 'foo' => 1, 'bar' => 2 }")
    h.hash?.should be_true
    h["foo"].to_i64.should eq(1_i64)
    h["bar"].to_i64.should eq(2_i64)

    h["baz"] = 99
    h["baz"].to_i64.should eq(99_i64)
  end

  it "supports arithmetic and comparison operators" do
    a = Rubellite.eval("15")
    b = Rubellite.eval("3")

    (a + b).to_i64.should eq(18_i64)
    (a - b).to_i64.should eq(12_i64)
    (a * b).to_i64.should eq(45_i64)
    (a / b).to_i64.should eq(5_i64)

    (a > b).should be_true
    (a < b).should be_false
    (a == Rubellite.eval("15")).should be_true
  end
end
