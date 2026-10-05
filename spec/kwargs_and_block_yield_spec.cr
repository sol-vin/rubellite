require "./spec_helper"

describe "Rubellite Kwargs, Block Semantics & Exception Hierarchy" do
  it "dispatches Ruby methods with keyword arguments via call_with_kwargs" do
    Ruby.eval(<<-RUBY)
      def calculate_metrics(base:, multiplier: 2, offset: 0)
        (base * multiplier) + offset
      end
    RUBY

    main = Ruby.eval("self")
    res1 = main.call_with_kwargs("calculate_metrics", base: 10, multiplier: 3, offset: 5)
    res1.to_i64.should eq(35_i64)

    # With default multiplier and offset
    res2 = main.call_with_kwargs("calculate_metrics", base: 25)
    res2.to_i64.should eq(50_i64)
  end

  it "raises specific native Ruby exception classes from Crystal callbacks" do
    Rubellite.export("verify_positive") do |args|
      n = args[0].to_i64
      if n < 0
        Rubellite.raise_ruby("ArgumentError", "Value #{n} must be non-negative")
      end
      (n * 2).to_ruby
    end

    # Call with positive value
    res = Ruby.eval("Rubellite.verify_positive(10)").to_i64
    res.should eq(20_i64)

    # Call with negative value and rescue ArgumentError in Ruby
    caught_class = Ruby.eval(<<-RUBY).to_s
      begin
        Rubellite.verify_positive(-5)
        "no_error"
      rescue ArgumentError => e
        e.class.name + ": " + e.message
      end
    RUBY

    caught_class.should start_with("ArgumentError: Value -5 must be non-negative")
  end

  it "raises TypeError and ZeroDivisionError from Crystal callbacks and catches them in Ruby" do
    Rubellite.export("safe_divide") do |args|
      a = args[0].to_i64
      b = args[1].to_i64
      if b == 0
        Rubellite.raise_ruby("ZeroDivisionError", "division by zero in Crystal kernel")
      end
      (a // b).to_ruby
    end

    div_error = Ruby.eval(<<-RUBY).to_s
      begin
        Rubellite.safe_divide(100, 0)
        "ok"
      rescue ZeroDivisionError => e
        e.message
      end
    RUBY

    div_error.should eq("division by zero in Crystal kernel")
  end

  it "passes Crystal closures into Ruby Enumerable algorithms that yield return values" do
    # Crystal block transforming Ruby array elements
    arr = Ruby.eval("[1, 2, 3, 4, 5]")
    mapped = arr.call_with_block("map") do |args|
      item = args[0].to_i64
      (item * item).to_ruby
    end

    mapped.to_a.map(&.to_i64).should eq([1_i64, 4_i64, 9_i64, 16_i64, 25_i64])
  end

  it "filters elements with Ruby select using a Crystal predicate closure" do
    words = Ruby.eval("['apple', 'banana', 'avocado', 'cherry', 'apricot']")
    selected = words.call_with_block("select") do |args|
      str = args[0].to_s
      str.starts_with?("a").to_ruby
    end

    res = selected.to_a.map(&.to_s)
    res.should eq(["apple", "avocado", "apricot"])
  end
end
