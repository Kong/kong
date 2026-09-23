--------------------------------------------------------------------------------
-- Kong plugin interface for Wasm filters
--------------------------------------------------------------------------------
local typedefs = require "kong.db.schema.typedefs"
local wasm = require "kong.runloop.wasm"


local wasm_filter_config

-- lazily load the filter schema as late as possible because it may-or-may-not
-- branch based on the contents of `kong.configuration`
local function load_filter_config_schema()
  if not wasm_filter_config then
    local wasm_filter = require "kong.db.schema.others.wasm_filter"

    for i = 1, #wasm_filter.fields do
      local field = wasm_filter.fields[i]
      local k, v = next(field)
      if k == "config" then
        wasm_filter_config = v
        break
      end
    end
    assert(wasm_filter_config)
  end

  return wasm_filter_config
end


local plugins = {}


function plugins.load_plugin(name)
  if not wasm.filters_by_name[name] then
    return false, "no such Wasm plugin"
  end

  -- XXX: in the future these values may be sourced from filter metadata
  local handler = {
    PRIORITY = 0,
    VERSION = "0.1.0",
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
      { config = load_filter_config_schema() },
    },
    entity_checks = {
      { mutually_exclusive = { "service", "route", } },
      { at_least_one_of = { "service", "route", } },
    },
  }

  return true, schema
end


return plugins
