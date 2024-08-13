--------------------------------------------------------------------------------
-- Kong plugin interface for Wasm filters
--------------------------------------------------------------------------------
local typedefs = require "kong.db.schema.typedefs"
local wasm = require "kong.runloop.wasm"
local wasm_filter = require "kong.db.schema.others.wasm_filter"


local wasm_filter_config
for i = 1, #wasm_filter.fields do
  local field = wasm_filter.fields[i]
  local k, v = next(field)
  if k == "config" then
    wasm_filter_config = v
    break
  end
end
assert(wasm_filter_config)


local plugins = {}


function plugins.load_plugin(name)
  if not wasm.filters_by_name[name] then
    return false, "no such Wasm plugin"
  end

  local handler = {
    PRIORITY = 0, -- FIXME
    VERSION = "0.1.0", -- FIXME
  }

  return true, handler
end


function plugins.load_schema(name)
  if not wasm.filters_by_name[name] then
    return false, "no such Wasm plugin"
  end

  local schema = {
    name = name,
    fields = {
      { name = { type = "string" } },
      { consumer = typedefs.no_consumer },
      { protocols = typedefs.protocols_http },
      { config = wasm_filter_config },
    },
  }

  return true, schema
end


return plugins
