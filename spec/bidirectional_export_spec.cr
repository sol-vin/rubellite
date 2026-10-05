require "./spec_helper"

describe "Rubellite Bidirectional Function Export & ClassBuilder" do
  it "exports a Crystal function callable from Ruby via Rubellite module" do
    # Export a Crystal function to Ruby
    Rubellite.export("crystal_multiply") do |args|
      a = args[0].to_i64
      b = args[1].to_i64
      (a * b).to_ruby
    end

    # Call it from Ruby
    result = Ruby.eval("Rubellite.crystal_multiply(6, 7)")
    result.to_i64.should eq(42_i64)
  end

  it "handles string manipulation in exported functions" do
    Rubellite.export("crystal_shout") do |args|
      str = args[0].to_s
      "#{str.upcase}!!!".to_ruby
    end

    res = Ruby.eval("Rubellite.crystal_shout('gemstone')")
    res.to_s.should eq("GEMSTONE!!!")
  end

  it "defines new Ruby classes with working Crystal methods via ClassBuilder" do
    builder = Rubellite::ClassBuilder.new("CrystalTransformer")
    builder.def_method("transform") do |args|
      val = args[0].to_i64
      (val * 10 + 5).to_ruby
    end

    # Use in Ruby
    res = Ruby.eval(<<-RUBY)
      transformer = CrystalTransformer.new
      transformer.transform(9)
    RUBY
    res.to_i64.should eq(95_i64)
  end

  it "handles multiple arguments in ClassBuilder methods" do
    builder = Rubellite::ClassBuilder.new("CrystalConcatenator")
    builder.def_method("join_strings") do |args|
      joined = args.map(&.to_s).join(" - ")
      joined.to_ruby
    end

    res = Ruby.eval("CrystalConcatenator.new.join_strings('one', 'two', 'three')")
    res.to_s.should eq("one - two - three")
  end

  it "propagates exceptions raised in Crystal callbacks to Ruby" do
    Rubellite.export("crystal_failing_function") do |_args|
      raise "Intentional Crystal Error"
    end

    # Ruby should receive RuntimeError
    expect_raises(Rubellite::Error, /Intentional Crystal Error/) do
      Ruby.eval("Rubellite.crystal_failing_function")
    end
  end
end
