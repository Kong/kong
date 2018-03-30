local kong_sdk = require "kong.sdk"
local meta = require "kong.meta"


-- preload latest sdk by default
local latest_sdk = kong_sdk.new()


local sdk_instances = {
  [kong_sdk.major_versions.latest] = latest_sdk,
}


local kong = {
  version = tostring(meta._VERSION),
  version_num = tonumber(string.format("%d%.2d%.2d",
                         meta._VERSION_TABLE.major * 100,
                         meta._VERSION_TABLE.minor * 10,
                         meta._VERSION_TABLE.patch)),

  current_sdk = latest_sdk,
}


local kong_mt = {}


do
  local rawget = rawget

  function kong_mt.__index(t, k)
    local f = rawget(kong_mt, k)
    if f then
      return f
    end

    local current_sdk = rawget(t, "current_sdk")
    if current_sdk then
      return current_sdk[k]
    end
  end
end


function kong_mt.swap_sdk(major_version)
  if major_version and type(major_version) ~= "number" then
    error("major_version must be a number", 2)
  end

  if not major_version then
    major_version = kong_sdk.major_versions.latest
  end

  local sdk = sdk_instances[major_version]
  if not sdk then
    sdk = kong_sdk.new(major_version)
    sdk_instances[major_version] = sdk
  end

  kong.current_sdk = sdk
end


return setmetatable(kong, kong_mt)
