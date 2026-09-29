require "./spec_helper"

describe "Rubellite Methods and Block Yielding" do
  it "calls Ruby methods with arbitrary arguments" do
    str = Rubellite.eval("'hello world'")
    upcased = str.call("upcase")
    upcased.to_s.should eq("HELLO WORLD")

    replaced = str.call("gsub", "world", "crystal")
    replaced.to_s.should eq("hello crystal")
  end

  it "passes Crystal blocks to Ruby Enumerable methods" do
    nums = Rubellite.eval("[1, 2, 3, 4, 5]")

    # Pass Crystal block into Ruby map
    doubled = nums.call_with_block("map") do |args|
      (args.first.to_i64 * 10).to_ruby
    end

    doubled.to_a.map(&.to_i64).should eq([10_i64, 20_i64, 30_i64, 40_i64, 50_i64])
  end

  it "filters with select and a Crystal block" do
    nums = Rubellite.eval("[1, 2, 3, 4, 5, 6]")

    evens = nums.call_with_block("select") do |args|
      (args.first.to_i64 % 2 == 0).to_ruby
    end

    evens.to_a.map(&.to_i64).should eq([2_i64, 4_i64, 6_i64])
  end
end
