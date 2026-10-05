require "./rubellite/c_api"
require "./rubellite/exception"
require "./rubellite/value"
require "./rubellite/convert"
require "./rubellite/engine"
require "./rubellite/gc"
require "./rubellite/concurrency"
require "./rubellite/channel"
require "./rubellite/macros"
require "./rubellite/spinel"
require "./rubellite/diagnostics/r2"
require "./rubellite/ext/extension"

require "./rubellite/version"

{% unless flag?(:release) %}
  require "./rubellite/docs"
{% end %}

# Rubellite: High-performance Crystal <-> Ruby interop bindings,
# Spinel AOT compiler fast-path, Channel concurrency, and radare2 diagnostics.
module Rubellite
end
