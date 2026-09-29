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
    Rubellite::Value.new(LibRuby.rb_int2inum(self.to_i64))
  end
end

struct Float
  def to_ruby : Rubellite::Value
    Rubellite::Value.new(LibRuby.rb_float_new(self.to_f64))
  end
end

class String
  def to_ruby : Rubellite::Value
    raw = LibRuby.rb_str_new(self.to_unsafe, self.bytesize.to_i64)
    Rubellite::Value.new(raw)
  end
end

struct Symbol
  def to_ruby : Rubellite::Value
    id = LibRuby.rb_intern(self.to_s.to_unsafe)
    val = (id << 8) | LibRuby::SYMBOL_FLAG
    Rubellite::Value.new(val)
  end
end

class Array(T)
  def to_ruby : Rubellite::Value
    ary = LibRuby.rb_ary_new_capa(self.size.to_i64)
    self.each do |elem|
      rb_val = elem.is_a?(Rubellite::Value) ? elem.raw : elem.to_ruby.raw
      LibRuby.rb_ary_push(ary, rb_val)
    end
    Rubellite::Value.new(ary)
  end
end

class Hash(K, V)
  def to_ruby : Rubellite::Value
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
    ary = LibRuby.rb_ary_new_capa(self.size.to_i64)
    {% for i in 0...T.size %}
      LibRuby.rb_ary_push(ary, self[{{i}}].to_ruby.raw)
    {% end %}
    Rubellite::Value.new(ary)
  end
end

struct NamedTuple
  def to_ruby : Rubellite::Value
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
  end
end
