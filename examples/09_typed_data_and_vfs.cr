require "../src/rubellite"

puts "=== Rubellite Next-Gen Innovations Demonstration ==="

# -----------------------------------------------------------------------------
# 1. Rubellite::TypedData(T): Zero-Copy Wrapping with Dual GC Lifecycle Safety
# -----------------------------------------------------------------------------
puts "\n[1] Rubellite::TypedData: Native Object Wrapping"

class Particle
  include Rubellite::TypedDataMixin

  property x : Float64
  property y : Float64
  property vx : Float64
  property vy : Float64

  def initialize(@x : Float64, @y : Float64, @vx : Float64, @vy : Float64)
  end

  def step(dt : Float64) : self
    @x += @vx * dt
    @y += @vy * dt
    self
  end

  def speed : Float64
    Math.hypot(@vx, @vy)
  end
end

# Export particle methods to Ruby
Rubellite::TypedData(Particle).def_method("step") do |p, args|
  dt = args[0].to_f64
  p.step(dt)
  p.to_ruby
end

Rubellite::TypedData(Particle).def_method("speed") do |p, _args|
  p.speed.to_ruby
end

Rubellite::TypedData(Particle).def_method("x") do |p, _args|
  p.x.to_ruby
end

Rubellite::TypedData(Particle).def_method("y") do |p, _args|
  p.y.to_ruby
end

particle = Particle.new(0.0, 0.0, 10.0, 20.0)
rb_particle = particle.to_ruby

puts "  Crystal Particle wrapped into Ruby: #{rb_particle.class_name}"
puts "  Initial speed: #{rb_particle.call("speed").to_f64.round(2)}"

# Advance in Ruby:
rb_particle.call("step", 0.5)
puts "  After 0.5s simulation in Ruby: x=#{particle.x}, y=#{particle.y}"

# Unbox directly in Crystal with zero copy:
unwrapped = rb_particle.as_typed_data(Particle)
puts "  Unwrapped identical instance? #{unwrapped.same?(particle)}"

# -----------------------------------------------------------------------------
# 2. Rubellite::VFS: In-Memory Virtual Filesystem with Zero Disk I/O
# -----------------------------------------------------------------------------
puts "\n[2] Rubellite::VFS: In-Memory Virtual Gem Distribution"

vfs_module_code = <<-'RUBY'
  module InMemAnalytics
    def self.variance(numbers)
      mean = numbers.sum.to_f / numbers.size
      numbers.map { |x| (x - mean) ** 2 }.sum / numbers.size
    end

    def self.std_dev(numbers)
      Math.sqrt(variance(numbers))
    end
  end
RUBY

Rubellite::VFS.mount("in_mem_analytics", vfs_module_code)
puts "  Mounted virtual module: #{Rubellite::VFS.files.inspect}"

# Require with standard Ruby require syntax
Rubellite.require("in_mem_analytics")

res = Rubellite.eval("InMemAnalytics.std_dev([10, 12, 23, 23, 16, 23, 21, 16])").to_f64
puts "  In-memory VFS module execution result: #{res.round(3)}"

# -----------------------------------------------------------------------------
# 3. Spinel::Vector(T): Contiguous SIMD Buffer & BLAS Operations
# -----------------------------------------------------------------------------
puts "\n[3] Spinel::Vector: High-Performance Vector Math"

vec_a = Rubellite::Spinel::Vector(Float64).new([1.0, 2.0, 3.0, 4.0, 5.0])
vec_b = Rubellite::Spinel::Vector(Float64).new([2.0, 3.0, 4.0, 5.0, 6.0])

dot_prod = vec_a.dot(vec_b)
l2_norm = vec_a.norm

puts "  Vector A: #{vec_a}"
puts "  Vector B: #{vec_b}"
puts "  Dot Product (A . B): #{dot_prod}"
puts "  Euclidean Norm ||A||: #{l2_norm.round(4)}"

# In-place BLAS axpy: y = 2.0 * x + y
vec_b.axpy!(2.0, vec_a)
puts "  After axpy!(2.0, A): #{vec_b}"

# -----------------------------------------------------------------------------
# 4. Rubellite::Profiler: YARV Bytecode Disassembly & Benchmark Telemetry
# -----------------------------------------------------------------------------
puts "\n[4] Rubellite::Profiler: YARV Bytecode Telemetry"

code_to_disasm = "x = 100; y = 200; (x * y) + 42"
bytecode = Rubellite::Profiler.disasm_ruby(code_to_disasm)
puts "  Disassembled YARV Bytecode:\n"
bytecode.lines.first(6).each do |line|
  puts "    #{line.strip}"
end

report = Rubellite::Profiler.compare(
  iterations: 500,
  ruby_action: ->{ Rubellite.eval("100 * 200 + 42"); nil },
  spinel_action: ->{ _ = 100 * 200 + 42; nil }
)

puts "\n#{report}"
puts "=== Demonstration Completed Successfully! ==="
