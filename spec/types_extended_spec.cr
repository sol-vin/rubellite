require "./spec_helper"

describe "Rubellite Extended Types & Boundary Interop" do
  it "converts Ruby Time to native Crystal Time with microsecond precision" do
    # 2026-01-15 12:30:45.500000 UTC
    ruby_time = Ruby.eval("Time.utc(2026, 1, 15, 12, 30, 45, 500000)")
    ruby_time.time?.should be_true

    crystal_time = ruby_time.to_time
    crystal_time.year.should eq(2026)
    crystal_time.month.should eq(1)
    crystal_time.day.should eq(15)
    crystal_time.hour.should eq(12)
    crystal_time.minute.should eq(30)
    crystal_time.second.should eq(45)
    crystal_time.millisecond.should eq(500)
  end

  it "converts native Crystal Time to Ruby Time" do
    cr_time = Time.utc(2026, 10, 4, 18, 0, 0, nanosecond: 250_000_000)
    rb_time = cr_time.to_ruby

    rb_time.time?.should be_true
    rb_time.call("year").to_i32.should eq(2026)
    rb_time.call("month").to_i32.should eq(10)
    rb_time.call("day").to_i32.should eq(4)
    rb_time.call("usec").to_i64.should eq(250_000_i64)
  end

  it "inspects and unboxes Ruby Range objects (inclusive and exclusive)" do
    inc_range = Ruby.eval("1..10")
    inc_range.range?.should be_true
    cr_inc = inc_range.to_range.not_nil!
    cr_inc.begin.should eq(1_i64)
    cr_inc.end.should eq(10_i64)
    cr_inc.exclusive?.should be_false

    exc_range = Ruby.eval("5...15")
    exc_range.range?.should be_true
    cr_exc = exc_range.to_range.not_nil!
    cr_exc.begin.should eq(5_i64)
    cr_exc.end.should eq(15_i64)
    cr_exc.exclusive?.should be_true
  end

  it "converts native Crystal Range to Ruby Range" do
    cr_range = (100_i64..200_i64)
    rb_range = cr_range.to_ruby
    rb_range.range?.should be_true

    sum = rb_range.call("to_a").call("sum").to_i64
    sum.should eq((100_i64..200_i64).sum)
  end

  it "unboxes Ruby Set objects into Crystal Set" do
    Ruby.require("set")
    rb_set = Ruby.eval("Set.new(['alpha', 'beta', 'gamma'])")
    rb_set.set?.should be_true

    cr_set = Set.new(rb_set.to_set.map(&.to_s))
    cr_set.should be_a(Set(String))
    cr_set.size.should eq(3)
    cr_set.includes?("beta").should be_true
  end

  it "evaluates Ruby Regexp pattern matching and extracts capture groups" do
    rb_regex = Ruby.eval("/user_([a-z]+)_id_(\\d+)/")
    rb_regex.regex?.should be_true

    match_data = rb_regex.call("match", "user_alice_id_9482")
    match_data.ruby_nil?.should be_false
    match_data[1].to_s.should eq("alice")
    match_data[2].to_i64.should eq(9482_i64)
  end

  it "unboxes Ruby Rational and Complex numbers accurately" do
    rat = Ruby.eval("Rational(7, 3)")
    rat.rational?.should be_true
    rat.call("numerator").to_i64.should eq(7_i64)
    rat.call("denominator").to_i64.should eq(3_i64)

    cmp = Ruby.eval("Complex(3, 4)")
    cmp.complex?.should be_true
    cmp.call("real").to_i64.should eq(3_i64)
    cmp.call("imag").to_i64.should eq(4_i64)
    cmp.call("abs").to_f64.should eq(5.0)
  end

  it "handles floating-point special values (Infinity, -Infinity, NaN)" do
    pos_inf = Ruby.eval("1.0 / 0.0")
    pos_inf.to_f64.infinite?.should eq(1)

    neg_inf = Ruby.eval("-1.0 / 0.0")
    neg_inf.to_f64.infinite?.should eq(-1)

    nan = Ruby.eval("0.0 / 0.0")
    nan.to_f64.nan?.should be_true
  end

  it "invokes Ruby methods with keyword arguments via call_with_kwargs" do
    Ruby.eval(<<-'RUBY')
      def format_profile(name:, age:, role: "engineer")
        "#{name} (#{age}) - #{role}"
      end
    RUBY

    main_obj = Ruby.eval("self")
    res = main_obj.call_with_kwargs("format_profile", name: "David", age: 34, role: "architect")
    res.to_s.should eq("David (34) - architect")

    # With default role
    res_def = main_obj.call_with_kwargs("format_profile", name: "Elena", age: 29)
    res_def.to_s.should eq("Elena (29) - engineer")
  end
end
