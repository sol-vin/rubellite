require "../typed_data"

module Rubellite
  module Spinel
    # High-performance contiguous typed vector with SIMD math operations
    # and zero-copy CRuby TypedData interoperability.
    class Vector(T)
      include Rubellite::TypedDataMixin

      getter size : Int32
      getter buffer : Slice(T)

      def initialize(size : Int32)
        @size = size
        @buffer = Slice(T).new(size)
      end

      def initialize(elements : Array(T))
        @size = elements.size
        @buffer = Slice(T).new(elements.size)
        elements.each_with_index { |v, i| @buffer[i] = v }
      end

      def initialize(elements : Enumerable(T))
        arr = elements.to_a
        @size = arr.size
        @buffer = Slice(T).new(arr.size)
        arr.each_with_index { |v, i| @buffer[i] = v }
      end

      def initialize(@buffer : Slice(T))
        @size = @buffer.size
      end

      def [](index : Int) : T
        @buffer[index]
      end

      def []=(index : Int, val : T) : T
        @buffer[index] = val
      end

      def to_a : Array(T)
        @buffer.to_a
      end

      def to_slice : Slice(T)
        @buffer
      end

      def to_unsafe : Pointer(T)
        @buffer.to_unsafe
      end

      # Computes the dot product of two vectors
      def dot(other : Vector(T)) : T
        if @size != other.size
          raise ArgumentError.new("Vector dimension mismatch: #{@size} vs #{other.size}")
        end

        sum = T.zero
        ptr_a = to_unsafe
        ptr_b = other.to_unsafe

        @size.times do |i|
          sum += ptr_a[i] * ptr_b[i]
        end
        sum
      end

      # Computes the Euclidean (L2) norm
      def norm : Float64
        Math.sqrt(norm_squared.to_f64)
      end

      # Computes the squared Euclidean norm
      def norm_squared : Float64
        sum = 0.0
        ptr = to_unsafe
        @size.times do |i|
          v = ptr[i].to_f64
          sum += v * v
        end
        sum
      end

      # Computes the sum of all elements
      def sum : T
        res = T.zero
        ptr = to_unsafe
        @size.times do |i|
          res += ptr[i]
        end
        res
      end

      # In-place scalar multiplication
      def scale!(factor : Number) : self
        f = T.new(factor)
        ptr = to_unsafe
        @size.times do |i|
          ptr[i] = (ptr[i] * f).as(T)
        end
        self
      end

      # Out-of-place scalar multiplication
      def scale(factor : Number) : Vector(T)
        dup = Vector(T).new(@size)
        f = T.new(factor)
        src = to_unsafe
        dst = dup.to_unsafe
        @size.times do |i|
          dst[i] = (src[i] * f).as(T)
        end
        dup
      end

      # In-place BLAS axpy operation: self = factor * other + self
      def axpy!(factor : Number, other : Vector(T)) : self
        if @size != other.size
          raise ArgumentError.new("Dimension mismatch in axpy!: #{@size} vs #{other.size}")
        end
        f = T.new(factor)
        dst = to_unsafe
        src = other.to_unsafe
        @size.times do |i|
          dst[i] = (dst[i] + f * src[i]).as(T)
        end
        self
      end

      # In-place element-wise addition: self += other
      def add!(other : Vector(T)) : self
        if @size != other.size
          raise ArgumentError.new("Dimension mismatch in add!: #{@size} vs #{other.size}")
        end
        dst = to_unsafe
        src = other.to_unsafe
        @size.times do |i|
          dst[i] = (dst[i] + src[i]).as(T)
        end
        self
      end

      # In-place element-wise multiplication: self *= other
      def multiply!(other : Vector(T)) : self
        if @size != other.size
          raise ArgumentError.new("Dimension mismatch in multiply!: #{@size} vs #{other.size}")
        end
        dst = to_unsafe
        src = other.to_unsafe
        @size.times do |i|
          dst[i] = (dst[i] * src[i]).as(T)
        end
        self
      end

      def to_s(io : IO) : Nil
        io << "Vector(" << T.name << ")["
        @size.times do |i|
          io << ", " if i > 0
          io << @buffer[i]
        end
        io << "]"
      end

      def inspect(io : IO) : Nil
        to_s(io)
      end

      # Registers Ruby methods on the wrapped CRuby class
      def self.setup_ruby_methods! : Nil
        Rubellite::TypedData(Vector(T)).wrap_name = "SpinelVector#{T.name.gsub(/[^A-Za-z0-9]/, "")}"

        Rubellite::TypedData(Vector(T)).def_method("size") do |vec, _args|
          vec.size.to_ruby
        end

        Rubellite::TypedData(Vector(T)).def_method("length") do |vec, _args|
          vec.size.to_ruby
        end

        Rubellite::TypedData(Vector(T)).def_method("sum") do |vec, _args|
          vec.sum.to_ruby
        end

        Rubellite::TypedData(Vector(T)).def_method("norm") do |vec, _args|
          vec.norm.to_ruby
        end

        Rubellite::TypedData(Vector(T)).def_method("to_a") do |vec, _args|
          vec.to_a.to_ruby
        end

        Rubellite::TypedData(Vector(T)).def_method("[]") do |vec, args|
          idx = args[0].to_i64.to_i32
          vec[idx].to_ruby
        end

        Rubellite::TypedData(Vector(T)).def_method("[]=") do |vec, args|
          idx = args[0].to_i64.to_i32
          val = args[1]
          num = {% if T == Float64 || T == Float32 %} val.to_f64 {% else %} val.to_i64 {% end %}
          vec[idx] = T.new(num)
          val
        end

        Rubellite::TypedData(Vector(T)).def_method("scale!") do |vec, args|
          val = args[0]
          num = {% if T == Float64 || T == Float32 %} val.to_f64 {% else %} val.to_i64 {% end %}
          vec.scale!(num)
          vec.to_ruby
        end

        Rubellite::TypedData(Vector(T)).def_method("dot") do |vec, args|
          other_val = args[0]
          other = Rubellite::TypedData(Vector(T)).unwrap(other_val)
          vec.dot(other).to_ruby
        end
      end
    end
  end
end
