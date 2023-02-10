local kong = kong
local kong_meta = require "kong.meta"
local proxy_wasm = require "resty.http.proxy_wasm"
local schema = require "kong.plugins.proxy-wasm.schema"


local ipairs = ipairs
local insert = table.insert


local ProxyWasmHandler = {
  VERSION = "0.0.1",
  PRIORITY = 1500, -- TODO: choose
}


function ProxyWasmHandler:init_worker()
  --[[
  -- WIP: internal ngx_wasm_module refactor for root ctx/req ctx distinction
  local db = kong.db
  local filters, seen = {}, {}

  for plugin, err in db.plugins:each(nil, { name = schema.name }) do
    if err then
      ngx.log(ngx.CRIT, "could not load routes: " .. err)
      return
    end

    for _, filter in ipairs(plugin.config.filters) do
      if not seen[filter.name] then
        insert(filters, {
          name = filter.name,
          config = filter.config,
        })

        seen[filter.name] = true
      end
    end
  end

  local root_c_ops, err = proxy_wasm.new(filters, true)
  if not root_c_ops then
    ngx.log(ngx.CRIT, err)
  end
  --]]
end


function ProxyWasmHandler:access(conf)
  ngx.log(ngx.INFO, "in access")

  local c_ops, err = proxy_wasm.new(conf.filters)
  if not c_ops then
    error(err)
  end

  local ok, err = proxy_wasm.attach(c_ops)
  if not ok then
    error(err)
  end
end


function ProxyWasmHandler:header_filter(conf)
  ngx.log(ngx.INFO, "in header_filter")
end


function ProxyWasmHandler:body_filter(conf)
  ngx.log(ngx.INFO, "in body_filter")
end


function ProxyWasmHandler:log(conf)
  ngx.log(ngx.INFO, "in log")
end


return ProxyWasmHandler
