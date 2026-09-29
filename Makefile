CRYSTAL ?= crystal
SHARDS ?= shards

.PHONY: all build spec bench doctor examples docs clean import-lib

all: build

build:
	$(SHARDS) build rubellite

spec:
	$(CRYSTAL) spec --verbose spec/all_spec.cr

bench: build
	./bin/rubellite bench

doctor: build
	./bin/rubellite doctor

examples:
	$(CRYSTAL) run examples/01_basic_eval.cr
	$(CRYSTAL) run examples/02_type_conversions_and_hash.cr
	$(CRYSTAL) run examples/03_calling_ruby_methods_and_blocks.cr
	$(CRYSTAL) run examples/04_defining_ruby_classes_in_crystal.cr
	$(CRYSTAL) run examples/05_channel_and_fiber_concurrency.cr
	$(CRYSTAL) run examples/06_spinel_aot_fastpath.cr
	$(CRYSTAL) run examples/07_r2_binary_forensics.cr

docs:
	$(CRYSTAL) docs

import-lib:
	$(CRYSTAL) run src/rubellite/tooling/import_lib_generator.cr

clean:
	rm -rf bin/ docs/ *.pdb *.obj *.exe
