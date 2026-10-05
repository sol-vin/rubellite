require "./spec_helper"

Rubellite.eval(<<-'RUBY')
  class AdvancedAccount
    attr_accessor :owner, :balance

    def initialize(owner, balance = 0)
      @owner = owner
      @balance = balance
    end

    def deposit(amount)
      @balance += amount
    end

    def withdraw(amount)
      @balance -= amount
    end

    def formatted_status
      "#{@owner}: $#{@balance}"
    end
  end
RUBY

class AccountProxy < Rubellite::Proxy
  ruby_target "AdvancedAccount"

  ruby_property owner : String
  ruby_property balance : Int64

  ruby_method deposit(amount : Int64), returns: Int64
  ruby_method withdraw(amount : Int64), returns: Int64
  ruby_method formatted_status, returns: String
end

describe "Rubellite Advanced Proxy & Properties" do
  it "instantiates proxy with constructor arguments" do
    account = AccountProxy.new("Alice", 1000_i64)
    account.owner.should eq("Alice")
    account.balance.should eq(1000_i64)
    account.formatted_status.should eq("Alice: $1000")
  end

  it "modifies attributes via generated setters" do
    account = AccountProxy.new("Bob", 500_i64)
    account.owner = "Robert"
    account.balance = 750_i64

    account.owner.should eq("Robert")
    account.balance.should eq(750_i64)
    account.formatted_status.should eq("Robert: $750")
  end

  it "invokes state-mutating methods and tracks return values" do
    account = AccountProxy.new("Charlie", 200_i64)
    new_bal = account.deposit(150_i64)
    new_bal.should eq(350_i64)
    account.balance.should eq(350_i64)

    rem_bal = account.withdraw(50_i64)
    rem_bal.should eq(300_i64)
    account.balance.should eq(300_i64)
  end
end
