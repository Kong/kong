-- TODO: get rid of 'kong.meta'; this module is king
local meta = require "kong.meta"
local SDK = require "kong.sdk"


local type = type
local setmetatable = setmetatable


local KONG_VERSION = tostring(meta._VERSION)
local KONG_VERSION_NUM = tonumber(string.format("%d%.2d%.2d",
                                  meta._VERSION_TABLE.major * 100,
                                  meta._VERSION_TABLE.minor * 10,
                                  meta._VERSION_TABLE.patch))


-- Runloop interface


local _GLOBAL = {}


function _GLOBAL.new()
  local self = {
    version = KONG_VERSION,
    version_num = KONG_VERSION_NUM,

    sdk_major_version = nil,
    sdk_version = nil,

    configuration = nil,
  }

  return setmetatable(self, _GLOBAL)
end


function _GLOBAL.set_named_ctx(self, name, key)
  if not self then
    error("arg #1 cannot be nil", 2)
  end

  if type(name) ~= "string" then
    error("name must be a string", 2)
  end

  if #name == 0 then
    error("name cannot be an empty string", 2)
  end

  if not self.ctx then
    error("ctx SDK module not initialized", 2)
  end

  self.ctx.keys[name] = key
end


function _GLOBAL.init_sdk(self, kong_config, sdk_major_version)
  if not self then
    error("arg #1 cannot be nil", 2)
  end

  return SDK.new(kong_config, sdk_major_version, self)
end


return _GLOBAL
