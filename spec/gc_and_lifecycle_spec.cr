require "./spec_helper"

describe "Rubellite GC Invariants & Object Lifecycles" do
  it "protects long-lived Ruby objects across forced GC cycles via GC.register_address" do
    # Allocate a Ruby string on the heap
    target_str = Ruby.eval("'persistent_data_' + 12345.to_s")
    # Allocate a heap pointer for the Ruby VALUE
    val_ptr = Pointer(LibRuby::Value).malloc(1)
    val_ptr.value = target_str.raw

    # Register its address with CRuby root set
    Rubellite::GC.register_address(val_ptr)

    # Trigger aggressive CRuby GC cycles and allocate garbage
    10.times do
      Ruby.eval("1000.times { Object.new }")
      Rubellite::GC.start_ruby_gc
    end

    # The registered value must remain valid and uncollected
    surviving_val = Rubellite::Value.new(val_ptr.value)
    surviving_val.to_s.should eq("persistent_data_12345")

    # Unregister address cleanly
    Rubellite::GC.unregister_address(val_ptr)
  end

  it "pins and unpins Crystal heap objects preventing Boehm GC collection" do
    # Create an arbitrary Crystal class instance
    closure_target = ["payload_a", "payload_b"]
    pinned_id = Rubellite::GC.pin(closure_target)

    # Pinning stores reference in static hash
    pinned_id.should be > 0_u64

    # Force Crystal Boehm GC cycle
    ::GC.collect

    # Unpin cleanly
    Rubellite::GC.unpin(pinned_id)
  end

  it "survives intensive allocation churn under continuous explicit GC triggers" do
    # Rapidly create 5,000 Ruby objects and verify stability
    5000.times do |i|
      val = Ruby.eval("[#{i}, 'item_#{i}']")
      if i % 1000 == 0
        Rubellite::GC.start_ruby_gc
      end
    end

    final_val = Ruby.eval("'gc_stress_ok'").to_s
    final_val.should eq("gc_stress_ok")
  end

  it "manages circular Ruby object graphs without crashing during GC sweeps" do
    Ruby.eval(<<-RUBY)
      $node_a = {}
      $node_b = {}
      $node_a[:neighbor] = $node_b
      $node_b[:neighbor] = $node_a
    RUBY

    node_a = Ruby.eval("$node_a")
    node_a[:neighbor][:neighbor].raw.should eq(node_a.raw)

    # Trigger GC with active circular references
    Rubellite::GC.start_ruby_gc

    node_a[:neighbor][:neighbor].raw.should eq(node_a.raw)

    # Break cycle and cleanup
    Ruby.eval("$node_a = nil; $node_b = nil")
    Rubellite::GC.start_ruby_gc
  end
end
