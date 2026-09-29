require "./spec_helper"

describe "Rubellite Exceptions" do
  it "catches Ruby runtime exceptions as Rubellite::Error" do
    expect_raises(Rubellite::Error) do
      Rubellite.eval("1 / 0")
    end
  end

  it "preserves Ruby error class and backtrace" do
    begin
      Rubellite.eval(<<-RUBY)
        def faulty_call
          raise ArgumentError, "Invalid argument supplied"
        end
        faulty_call
      RUBY
      fail("Expected exception not raised")
    rescue ex : Rubellite::Error
      ex.ruby_class.should eq("ArgumentError")
      ex.message.not_nil!.should contain("Invalid argument supplied")
      ex.ruby_backtrace.should_not be_empty
    end
  end
end
