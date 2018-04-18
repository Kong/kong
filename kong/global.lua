local kong_sdk = require "kong.sdk"
local base = require "kong.sdk.utils.base"
local meta = require "kong.meta"
local ctx = require "kong.ctx"


local rawget = rawget


local kong_mt = {}
local kong = {
  version = tostring(meta._VERSION),
  version_num = tonumber(string.format("%d%.2d%.2d",
                         meta._VERSION_TABLE.major * 100,
                         meta._VERSION_TABLE.minor * 10,
                         meta._VERSION_TABLE.patch)),

  new_tab = base.new_tab,
  clear_tab = base.clear_tab,

  latest_sdk = nil,
}


function kong_mt.__index(t, k)
  if k == "ctx" then
    return ctx.get_core_ctx()
  end

  local f = rawget(kong_mt, k)
  if f then
    return f
  end

  local sdk = rawget(kong_mt, "latest_sdk")
  if sdk then
    local sdk_f = sdk[k]
    if sdk_f then
      -- cache function for future lookups
      t[k] = sdk_f
      return sdk_f
    end
  end
end


function kong_mt.init(kong_config)
  kong.configuration = setmetatable({}, {
    __index = function(_, v)
      return kong_config[v]
    end,

    __newindex = function()
      error("cannot write to kong.configuration", 2)
    end,
  })

  -- init latest SDK version
  kong.latest_sdk = kong.get_sdk()
end


do
  local sdk_instances = {}

  function kong_mt.get_sdk(major_version)
    if major_version and type(major_version) ~= "number" then
      error("major_version must be a number", 2)
    end

    if not major_version then
      major_version = kong_sdk.major_versions.latest
    end

    local sdk = sdk_instances[major_version]
    if not sdk then
      sdk = kong_sdk.new(kong.configuration, major_version)
      sdk_instances[major_version] = sdk
    end

    return sdk
  end
end


return setmetatable(kong, kong_mt)
