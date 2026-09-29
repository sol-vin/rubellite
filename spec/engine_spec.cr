require "./spec_helper"

describe Rubellite::Engine do
  it "reports initialized status" do
    Rubellite.initialized?.should be_true
  end

  it "evaluates arithmetic expressions" do
    res = Rubellite.eval("10 * 5 + 3")
    res.to_i64.should eq(53_i64)
  end

  it "evaluates floating-point expressions" do
    res = Rubellite.eval("3.14159 * 2.0")
    res.to_f64.should be_close(6.28318, 0.001)
  end

  it "evaluates string expressions" do
    res = Rubellite.eval("'Hello from ' + 'CRuby!'")
    res.to_s.should eq("Hello from CRuby!")
  end

  it "resolves constants" do
    math = Rubellite["Math"]
    pi = math.call("sqrt", 16.0)
    pi.to_f64.should eq(4.0)
  end

  it "requires standard libraries" do
    Rubellite.require("digest").should be_a(Bool)
    sha = Rubellite.eval("Digest::SHA256.hexdigest('crystal')").to_s
    sha.size.should eq(64)
  end
end
