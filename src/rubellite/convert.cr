require "./c_api"
require "./value"

struct Nil
  def to_ruby : Rubellite::Value
    Rubellite::Value.new(LibRuby::Qnil)
  end
end

struct Bool
  def to_ruby : Rubellite::Value
    Rubellite::Value.new(self ? LibRuby::Qtrue : LibRuby::Qfalse)
  end
end

struct Int
  def to_ruby : Rubellite::Value
    Rubellite.ensure_init!
    Rubellite::Value.new(LibRuby.rb_int2inum(self.to_i64))
  end
end

struct Float
  def to_ruby : Rubellite::Value
    Rubellite.ensure_init!
    Rubellite::Value.new(LibRuby.rb_float_new(self.to_f64))
  end
end

class String
  def to_ruby : Rubellite::Value
    Rubellite.ensure_init!
    raw = LibRuby.rb_str_new(self.to_unsafe, self.bytesize.to_i64)
    Rubellite::Value.new(raw)
  end
end

struct Slice(T)
  def to_ruby : Rubellite::Value
    {% if T == UInt8 %}
      Rubellite.ensure_init!
      raw = LibRuby.rb_str_new(self.to_unsafe, self.size.to_i64)
      Rubellite::Value.new(raw)
    {% else %}
      to_a.to_ruby
    {% end %}
  end
end

struct Symbol
  def to_ruby : Rubellite::Value
    Rubellite.ensure_init!
    id = LibRuby.rb_intern(self.to_s.to_unsafe)
    val = (id << 8) | LibRuby::SYMBOL_FLAG
    Rubellite::Value.new(val)
  end
end

class Array(T)
  def to_ruby : Rubellite::Value
    Rubellite.ensure_init!
    ary = LibRuby.rb_ary_new_capa(self.size.to_i64)
    self.each do |elem|
      rb_val = elem.is_a?(Rubellite::Value) ? elem.raw : elem.to_ruby.raw
      LibRuby.rb_ary_push(ary, rb_val)
    end
    Rubellite::Value.new(ary)
  end
end

struct Set(T)
  def to_ruby : Rubellite::Value
    to_a.to_ruby
  end
end

struct Time
  def to_ruby : Rubellite::Value
    Rubellite.ensure_init!
    time_mod = Rubellite["Time"]
    time_mod.call("at", self.to_unix, (self.nanosecond // 1000).to_i64)
  end
end

struct Range(B, E)
  def to_ruby : Rubellite::Value
    Rubellite.ensure_init!
    range_mod = Rubellite["Range"]
    range_mod.call("new", self.begin.to_ruby, self.end.to_ruby, self.exclusive?.to_ruby)
  end
end

class Hash(K, V)
  def to_ruby : Rubellite::Value
    Rubellite.ensure_init!
    h = LibRuby.rb_hash_new
    self.each do |k, v|
      rb_k = k.is_a?(Rubellite::Value) ? k.raw : k.to_ruby.raw
      rb_v = v.is_a?(Rubellite::Value) ? v.raw : v.to_ruby.raw
      LibRuby.rb_hash_aset(h, rb_k, rb_v)
    end
    Rubellite::Value.new(h)
  end
end

struct Tuple
  def to_ruby : Rubellite::Value
    Rubellite.ensure_init!
    ary = LibRuby.rb_ary_new_capa(self.size.to_i64)
    {% for i in 0...T.size %}
      LibRuby.rb_ary_push(ary, self[{{i}}].to_ruby.raw)
    {% end %}
    Rubellite::Value.new(ary)
  end
end

struct NamedTuple
  def to_ruby : Rubellite::Value
    Rubellite.ensure_init!
    h = LibRuby.rb_hash_new
    {% for key in T.keys %}
      k_val = {{key.stringify}}.to_ruby.raw
      v_val = self[{{key.symbolize}}].to_ruby.raw
      LibRuby.rb_hash_aset(h, k_val, v_val)
    {% end %}
    Rubellite::Value.new(h)
  end
end

module Rubellite
  alias DeepValue = Nil | Bool | Int64 | Float64 | String | Rubellite::Value | Array(DeepValue) | Hash(String, DeepValue)

  struct Value
    # Converts a Crystal object to a Rubellite::Value
    def self.from(obj) : Value
      obj.to_ruby
    end

    # Auto-converts to Crystal primitive where possible
    def as_crystal
      if ruby_nil?
        nil
      elsif true?
        true
      elsif false?
        false
      elsif fixnum?
        to_i64
      elsif flonum?
        to_f64
      elsif string?
        to_s
      elsif symbol?
        symbol_name
      elsif array?
        to_a
      elsif hash?
        to_h
      else
        self
      end
    end

    # Recursive deep unboxer converting nested Arrays/Hashes into native Crystal collections
    def as_crystal_deep : DeepValue
      if ruby_nil?
        nil
      elsif true?
        true
      elsif false?
        false
      elsif fixnum?
        to_i64
      elsif flonum?
        to_f64
      elsif string?
        to_s
      elsif symbol?
        symbol_name
      elsif array?
        res = [] of DeepValue
        to_a.each do |elem|
          res << elem.as_crystal_deep
        end
        res
      elsif hash?
        res = {} of String => DeepValue
        to_h.each do |k, v|
          res[k.to_s] = v.as_crystal_deep
        end
        res
      else
        self
      end
    end

    # Typed unboxing for Arrays
    def to_a(type : T.class) : Array(T) forall T
      to_a.map do |elem|
        {% if T == String %}
          elem.to_s
        {% elsif T == Int64 %}
          elem.to_i64
        {% elsif T == Int32 %}
          elem.to_i32
        {% elsif T == Float64 %}
          elem.to_f64
        {% elsif T == Bool %}
          elem.to_bool
        {% else %}
          elem.as_crystal.as(T)
        {% end %}
      end
    end

    # Typed unboxing for Hashes
    def to_h(k_type : K.class, v_type : V.class) : Hash(K, V) forall K, V
      res = Hash(K, V).new
      to_h.each do |k, v|
        key = {% if K == String %}
                k.to_s
              {% elsif K == Symbol %}
                k.symbol_name.to_sym
              {% elsif K == Int32 %}
                k.to_i32
              {% elsif K == Int64 %}
                k.to_i64
              {% else %}
                k.as_crystal.as(K)
              {% end %}

        val = {% if V == String %}
                v.to_s
              {% elsif V == Int32 %}
                v.to_i32
              {% elsif V == Int64 %}
                v.to_i64
              {% elsif V == Float64 %}
                v.to_f64
              {% elsif V == Bool %}
                v.to_bool
              {% else %}
                v.as_crystal.as(V)
              {% end %}
        res[key] = val
      end
      res
    end

    # Convenience unboxers
    def as_i : Int32
      to_i32
    end

    def as_i64 : Int64
      to_i64
    end

    def as_f : Float64
      to_f64
    end

    def as_s : String
      to_s
    end

    def as_bool : Bool
      to_bool
    end

    def as_nil : Nil
      nil
    end
  end
end
