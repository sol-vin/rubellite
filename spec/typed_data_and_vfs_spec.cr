require "./spec_helper"

# Test Crystal class for TypedData wrapping
class SpecPoint
  include Rubellite::TypedDataMixin

  property x : Float64
  property y : Float64

  def initialize(@x : Float64, @y : Float64)
  end

  def distance : Float64
    Math.hypot(@x, @y)
  end

  def translate!(dx : Float64, dy : Float64) : self
    @x += dx
    @y += dy
    self
  end
end

# Test Crystal struct for value-type TypedData wrapping
struct SpecColor
  include Rubellite::TypedDataMixin

  getter r : UInt8
  getter g : UInt8
  getter b : UInt8

  def initialize(@r : UInt8, @g : UInt8, @b : UInt8)
  end

  def hex : String
    sprintf("#%02X%02X%02X", @r, @g, @b)
  end
end

describe "Next-Gen Innovations: TypedData, VFS, Spinel::Vector, and Profiler" do
  before_all do
    Rubellite.ensure_init!

    # Setup TypedData methods on SpecPoint
    Rubellite::TypedData(SpecPoint).def_method("x") do |pt, _args|
      pt.x.to_ruby
    end

    Rubellite::TypedData(SpecPoint).def_method("y") do |pt, _args|
      pt.y.to_ruby
    end

    Rubellite::TypedData(SpecPoint).def_method("distance") do |pt, _args|
      pt.distance.to_ruby
    end

    Rubellite::TypedData(SpecPoint).def_method("translate!") do |pt, args|
      dx = args[0].to_f64
      dy = args[1].to_f64
      pt.translate!(dx, dy)
      pt.to_ruby
    end

    # Setup TypedData methods on SpecColor
    Rubellite::TypedData(SpecColor).def_method("hex") do |col, _args|
      col.hex.to_ruby
    end

    # Setup Spinel::Vector Ruby methods
    Rubellite::Spinel::Vector(Float64).setup_ruby_methods!
  end

  describe Rubellite::TypedData do
    it "wraps a Crystal class instance into CRuby RTypedData with zero copy" do
      pt = SpecPoint.new(3.0, 4.0)
      ruby_val = pt.to_ruby

      ruby_val.class_name.should eq("SpecPoint")
      ruby_val.typed_data?(SpecPoint).should be_true
      ruby_val.call("distance").to_f64.should eq(5.0)
      ruby_val.call("x").to_f64.should eq(3.0)
      ruby_val.call("y").to_f64.should eq(4.0)
    end

    it "reflects Crystal mutations in Ruby and vice versa" do
      pt = SpecPoint.new(1.0, 2.0)
      ruby_val = pt.to_ruby

      # Mutate in Crystal, verify in Ruby
      pt.x = 10.0
      ruby_val.call("x").to_f64.should eq(10.0)

      # Mutate from Ruby via translate!, verify in Crystal
      ruby_val.call("translate!", 5.0, 3.0)
      pt.x.should eq(15.0)
      pt.y.should eq(5.0)
    end

    it "unwraps the exact Crystal instance from a Ruby Value" do
      pt = SpecPoint.new(7.5, 9.25)
      ruby_val = pt.to_ruby

      unwrapped = ruby_val.as_typed_data(SpecPoint)
      unwrapped.should be(pt)
      unwrapped.x.should eq(7.5)
      unwrapped.y.should eq(9.25)
    end

    it "wraps and unwraps Crystal structs (value types)" do
      col = SpecColor.new(255_u8, 128_u8, 64_u8)
      ruby_val = col.to_ruby

      ruby_val.call("hex").to_s.should eq("#FF8040")

      unwrapped = ruby_val.as_typed_data(SpecColor)
      unwrapped.r.should eq(255_u8)
      unwrapped.g.should eq(128_u8)
      unwrapped.b.should eq(64_u8)
      unwrapped.hex.should eq("#FF8040")
    end

    it "provides safe type checking with typed_data? and as_typed_data?" do
      pt = SpecPoint.new(1.0, 2.0)
      ruby_val = pt.to_ruby
      str_val = "hello".to_ruby

      ruby_val.typed_data?(SpecPoint).should be_true
      ruby_val.typed_data?(SpecColor).should be_false
      str_val.typed_data?(SpecPoint).should be_false

      ruby_val.as_typed_data?(SpecPoint).should_not be_nil
      ruby_val.as_typed_data?(SpecColor).should be_nil
      str_val.as_typed_data?(SpecPoint).should be_nil
    end

    it "raises TypeException when unwrapping an incompatible Ruby object" do
      str_val = "not a point".to_ruby
      expect_raises(Rubellite::TypeException) do
        str_val.as_typed_data(SpecPoint)
      end
    end

    it "preserves object integrity across Ruby and Boehm GC cycles" do
      Rubellite.eval("$live_points = []")
      points = Array(SpecPoint).new
      ruby_points = Array(Rubellite::Value).new

      100.times do |i|
        p = SpecPoint.new(i.to_f64, (i * 2).to_f64)
        points << p
        rb_val = p.to_ruby
        ruby_points << rb_val
        Rubellite["$live_points"].call("push", rb_val)
      end

      # Trigger both Ruby GC and Boehm GC cycles
      Rubellite::GC.start_ruby_gc
      ::GC.collect

      # Verify all 100 wrapped objects are intact
      100.times do |i|
        pt = ruby_points[i].as_typed_data(SpecPoint)
        pt.x.should eq(i.to_f64)
        pt.y.should eq((i * 2).to_f64)
      end

      # Clear Ruby references and cycle GC
      Rubellite["$live_points"].call("clear")
      Rubellite::GC.start_ruby_gc
      ::GC.collect
    end
  end

  describe Rubellite::VFS do
    before_each do
      Rubellite::VFS.reset!
    end

    it "mounts and requires an in-memory Ruby script with zero disk I/O" do
      code = <<-RUBY
        module VfsCalc
          def self.multiply(a, b)
            a * b
          end
        end
      RUBY

      Rubellite::VFS.mount("vfs_calc", code)
      Rubellite::VFS.mounted?("vfs_calc").should be_true
      Rubellite::VFS.mounted?("vfs_calc.rb").should be_true

      # Require in Ruby
      Rubellite.eval("require 'vfs_calc'").to_bool.should be_true
      Rubellite.eval("VfsCalc.multiply(6, 7)").to_i64.should eq(42)

      # Idempotent require returns false
      Rubellite.eval("require 'vfs_calc'").to_bool.should be_false
    end

    it "supports requiring with explicit .rb extension" do
      code = <<-'RUBY'
        module VfsGreeter
          def self.greet(name)
            "Hello, #{name} from VFS!"
          end
        end
      RUBY

      Rubellite::VFS.mount("vfs_greeter.rb", code)
      Rubellite.eval("require 'vfs_greeter.rb'").to_bool.should be_true
      Rubellite.eval("VfsGreeter.greet('Crystal')").to_s.should eq("Hello, Crystal from VFS!")
    end

    it "supports multi-file modular virtual gems with internal requires" do
      Rubellite::VFS.mount("my_vfs_gem/math_ops", <<-'RUBY')
        module MyVfsGem
          module MathOps
            def self.power(base, exp)
              base ** exp
            end
          end
        end
      RUBY

      Rubellite::VFS.mount("my_vfs_gem", <<-'RUBY')
        require 'my_vfs_gem/math_ops'
        module MyVfsGem
          def self.cube(x)
            MathOps.power(x, 3)
          end
        end
      RUBY

      Rubellite.eval("require 'my_vfs_gem'").to_bool.should be_true
      Rubellite.eval("MyVfsGem.cube(4)").to_i64.should eq(64)
    end

    it "allows reading, unmounting, and inspecting mounted virtual files" do
      Rubellite::VFS.mount("temporary_vfs_file.rb", "MY_VFS_CONST = 12345")
      Rubellite::VFS.read("temporary_vfs_file.rb").should eq("MY_VFS_CONST = 12345")
      Rubellite::VFS.files.should contain("temporary_vfs_file.rb")

      Rubellite::VFS.unmount("temporary_vfs_file.rb").should be_true
      Rubellite::VFS.mounted?("temporary_vfs_file.rb").should be_false
      Rubellite::VFS.read("temporary_vfs_file.rb").should be_nil
    end

    it "mounts directories and gem bundles" do
      files = {
        "lib/fast_formatter.rb" => "module FastFormatter; def self.fmt(s); s.strip.downcase; end; end",
        "lib/fast_formatter/version.rb" => "module FastFormatter; VERSION = '1.0.0'; end"
      }
      Rubellite::VFS.mount_gem("fast_formatter", files)

      Rubellite.eval("require 'fast_formatter'").to_bool.should be_true
      Rubellite.eval("FastFormatter.fmt('  SPINEL  ')").to_s.should eq("spinel")
      Rubellite.eval("require 'fast_formatter/version'").to_bool.should be_true
      Rubellite.eval("FastFormatter::VERSION").to_s.should eq("1.0.0")
    end
  end

  describe Rubellite::Spinel::Vector do
    it "performs dot product correctly on Float64 vectors" do
      v1 = Rubellite::Spinel::Vector(Float64).new([1.0, 2.0, 3.0])
      v2 = Rubellite::Spinel::Vector(Float64).new([4.0, 5.0, 6.0])

      v1.dot(v2).should eq(32.0)
    end

    it "computes Euclidean norm and sum" do
      v = Rubellite::Spinel::Vector(Float64).new([3.0, 4.0])
      v.norm.should eq(5.0)
      v.sum.should eq(7.0)
    end

    it "performs in-place and out-of-place scaling" do
      v = Rubellite::Spinel::Vector(Float64).new([1.0, 2.0, 3.0])
      scaled = v.scale(2.0)
      scaled.to_a.should eq([2.0, 4.0, 6.0])
      v.to_a.should eq([1.0, 2.0, 3.0])

      v.scale!(3.0)
      v.to_a.should eq([3.0, 6.0, 9.0])
    end

    it "performs BLAS axpy operation (y = a*x + y)" do
      x = Rubellite::Spinel::Vector(Float64).new([1.0, 2.0, 3.0])
      y = Rubellite::Spinel::Vector(Float64).new([10.0, 20.0, 30.0])

      y.axpy!(2.0, x)
      y.to_a.should eq([12.0, 24.0, 36.0])
    end

    it "interoperates seamlessly with Ruby via TypedData methods" do
      v1 = Rubellite::Spinel::Vector(Float64).new([1.5, 2.5, 3.5])
      v2 = Rubellite::Spinel::Vector(Float64).new([2.0, 2.0, 2.0])

      rb_v1 = v1.to_ruby
      rb_v2 = v2.to_ruby

      rb_v1.call("size").to_i64.should eq(3)
      rb_v1.call("sum").to_f64.should eq(7.5)
      rb_v1.call("dot", rb_v2).to_f64.should eq(15.0)

      rb_v1.call("scale!", 2.0)
      rb_v1.call("to_a").to_a.map(&.to_f64).should eq([3.0, 5.0, 7.0])
    end
  end

  describe Rubellite::Profiler do
    it "disassembles Ruby code into YARV bytecode instruction sequences" do
      code = "a = 10; b = 20; a + b"
      disasm = Rubellite::Profiler.disasm_ruby(code)

      disasm.should contain("putobject")
      disasm.should contain("opt_plus")
      disasm.should contain("leave")
    end

    it "runs comparative benchmarks and generates profile reports" do
      counter = 0
      report = Rubellite::Profiler.compare(
        iterations: 100,
        ruby_action: ->{ Rubellite.eval("100 * 2"); nil },
        spinel_action: ->{ counter += 200; nil }
      )

      report.iterations.should eq(100)
      report.ruby_time.total_milliseconds.should be >= 0.0
      report.spinel_time.total_milliseconds.should be >= 0.0
      report.speedup.should be > 0.0

      report_str = report.to_s
      report_str.should contain("RUBELLITE PROFILER REPORT")
      report_str.should contain("Iterations:")
      report_str.should contain("Speedup Factor:")
    end
  end
end
