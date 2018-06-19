-- TODO: get rid of 'kong.meta'; this module is king
local meta = require "kong.meta"
local PDK = require "kong.pdk"
local phase_checker = require "kong.pdk.private.phases"


local type = type
local setmetatable = setmetatable


local KONG_VERSION = tostring(meta._VERSION)
local KONG_VERSION_NUM = tonumber(string.format("%d%.2d%.2d",
                                  meta._VERSION_TABLE.major * 100,
                                  meta._VERSION_TABLE.minor * 10,
                                  meta._VERSION_TABLE.patch))


-- Runloop interface


local _GLOBAL = {
  phases = phase_checker.phases,
}


function _GLOBAL.new()
  return {
    version = KONG_VERSION,
    version_num = KONG_VERSION_NUM,

    pdk_major_version = nil,
    pdk_version = nil,

    configuration = nil,
  }
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
    error("ctx PDK module not initialized", 2)
  end

  self.ctx.keys[name] = key
end


function _GLOBAL.set_phase(self, phase)
  if not self then
    error("arg #1 cannot be nil", 2)
  end

  local kctx = self.ctx
  if not kctx then
    error("ctx SDK module not initialized", 2)
  end

  kctx.core.phase = phase
end


do
  local log_facilities = {
    core = nil,
    namespaced = setmetatable({}, { __index = "k" }),
  }


  function _GLOBAL.set_namespaced_log(self, namespace)
    if not self then
      error("arg #1 cannot be nil", 2)
    end

    if type(namespace) ~= "string" then
      error("namespace (arg #2) must be a string", 2)
    end

    local log = log_facilities.namespaced[namespace]
    if not log then
      log = self.log.new(namespace) -- use default namespaced format
      log_facilities.namespaced[namespace] = log
    end

    self.log = log
  end


  function _GLOBAL.reset_log(self)
    if not self then
      error("arg #1 cannot be nil", 2)
    end

    self.log = log_facilities.core
  end


  function _GLOBAL.init_pdk(self, kong_config, pdk_major_version)
    if not self then
      error("arg #1 cannot be nil", 2)
    end

    PDK.new(kong_config, pdk_major_version, self)

    log_facilities.core = self.log
  end
end


return _GLOBAL
