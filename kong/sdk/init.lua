local MAJOR_VERSIONS = {
  [0] = {
    version = "0.0.1",
    modules = {
      "base",
      "ip",
      "request",
      "client",
    },
  },

  [1] = {
    version = "1.0.0",
    modules = {
      "base",
      "ip",
      "request",
      "client",
      "upstream",
      --[[
      "upstream.response",
      "response",
      "timers",
      "http",
      "utils",
      "shm",
      --]]
    },
  },

  latest = 1,
}


local _SDK = {
  major_versions = MAJOR_VERSIONS,
}

local _sdk_mt = {}


function _SDK.new(kong_config, major_version)
  if kong_config then
    if type(kong_config) ~= "table" then
      error("kong_config must be a table", 2)
    end

  else
    kong_config = {}
  end

  if major_version then
    if type(major_version) ~= "number" then
      error("major_version must be a number", 2)
    end

  else
    major_version = MAJOR_VERSIONS.latest
  end

  local version_meta = MAJOR_VERSIONS[major_version]

  local sdk = {
    sdk_major_version = major_version,
    sdk_version = version_meta.version,
    sdk_version_num = nil, -- TODO (not sure if needed at all)
  }

  for _, module_name in ipairs(version_meta.modules) do
    local mod = require("kong.sdk." .. module_name)

    if module_name == "base" then
      mod.new(sdk, major_version, kong_config)

    else
      sdk[module_name] = mod.new(sdk, major_version, kong_config)
    end
  end

  return setmetatable(sdk, _sdk_mt)
end


return _SDK
