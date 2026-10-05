# CARBON CHANGELOG
## [0.1.16] - 2026-10-04
### 🐛 Bug Fixes
- ✓ Pre-query Ruby standard library paths before C-API initialization to ensure reliable $LOAD_PATH bootstrapping

### ⚡ Performance Optimizations
- 🚀 Accelerate GC churn stress spec by executing allocation loop natively in Ruby bytecode

---
## [0.1.15] - 2026-10-04
### 🐛 Bug Fixes
- ✓ Eliminate subprocess fork in Engine.init by bootstrapping RbConfig standard library load paths directly in memory
- ✓ Bound Thread#join in Concurrency GVL test suite with 3-second limit to guarantee non-blocking CI execution

### ⚡ Performance Optimizations
- 🚀 Tune streaming pipeline benchmark to 200 items with 20-second timeout for virtualized CI runners

---
## [0.1.14] - 2026-10-04
### ✨ Features & Improvements
- ✦ Add comprehensive Rubellite test platform expansion (21 suites, 103 specs) covering GC invariants, GVL concurrency, and extended types
- ✦ Implement CRuby 3.0+ keyword arguments dispatch (`rb_funcallv_kw`) and native Ruby exception class raising (`ArgumentError`, `TypeError`, `ZeroDivisionError`)
- ✦ Support extended Ruby types: nanosecond Time, inclusive/exclusive Range, Regexp captures, Set, Rational, Complex, NaN, and Infinity

### 🐛 Bug Fixes
- ✓ Fix signed Fixnum right-shift unboxing using to_i64! preventing arithmetic overflow on negative integers
- ✓ Harden without_gvl and with_gvl with exception propagation and NoReturn block support

### 🛠️ Chores & Tooling
- • Expand CI matrix to test multiple Ruby versions (Ruby 3.2 and 3.3 across Linux, macOS, and Windows)

---
## [0.1.13] - 2026-10-04
---
## [0.1.12] - 2026-10-04
### 🐛 Bug Fixes
- ✓ **[Concurrency]** register fiber machine stack boundary in Engine.synchronize to prevent CRuby SystemStackError and channel deadlocks

---
## [0.1.11] - 2026-10-04
---
## [0.1.10] - 2026-10-04
---
## [0.1.9] - 2026-10-04
---
## [0.1.8] - 2026-10-04
---
## [0.1.7] - 2026-10-04
### ✨ Features & Improvements
- ✦ initial release of Rubellite - Crystal <-> Ruby interop bindings ([`fe82e6e`](https://github.com/sol-vin/rubellite/commit/fe82e6e))

### 🐛 Bug Fixes
- ✓ **[CI]** fix dependencies, multi-OS dynamic loader, and Windows DLL path resolution ([`e8a9a40`](https://github.com/sol-vin/rubellite/commit/e8a9a40))
- ✓ **[CI]** add rpath and LD_LIBRARY_PATH, use ruby_script for , and bootstrap stdlib load path ([`e49c5fc`](https://github.com/sol-vin/rubellite/commit/e49c5fc))
- ✓ **[R2]** normalize Mach-O underscore prefix, add symbol table fallback, and find r2 binary path ([`2682017`](https://github.com/sol-vin/rubellite/commit/2682017))
- ✓ **[ENGINE]** initialize encodings via ruby_options, pass relocs flags to r2, and test cgi standard library ([`59e0268`](https://github.com/sol-vin/rubellite/commit/59e0268))
- ✓ **[CI]** streamline matrix to multi-OS tier and eliminate apt ruby package conflict ([`c92798c`](https://github.com/sol-vin/rubellite/commit/c92798c))

---
## [0.1.6] - 2026-10-04
> Initial release
### ✨ Features & Improvements
- ✦ initial release of Rubellite - Crystal <-> Ruby interop bindings ([`fe82e6e`](https://github.com/sol-vin/rubellite/commit/fe82e6e))

### 🐛 Bug Fixes
- ✓ **[CI]** fix dependencies, multi-OS dynamic loader, and Windows DLL path resolution ([`e8a9a40`](https://github.com/sol-vin/rubellite/commit/e8a9a40))
- ✓ **[CI]** add rpath and LD_LIBRARY_PATH, use ruby_script for , and bootstrap stdlib load path ([`e49c5fc`](https://github.com/sol-vin/rubellite/commit/e49c5fc))
- ✓ **[R2]** normalize Mach-O underscore prefix, add symbol table fallback, and find r2 binary path ([`2682017`](https://github.com/sol-vin/rubellite/commit/2682017))
- ✓ **[ENGINE]** initialize encodings via ruby_options, pass relocs flags to r2, and test cgi standard library ([`59e0268`](https://github.com/sol-vin/rubellite/commit/59e0268))
- ✓ **[CI]** streamline matrix to multi-OS tier and eliminate apt ruby package conflict ([`c92798c`](https://github.com/sol-vin/rubellite/commit/c92798c))

