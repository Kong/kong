local clustering_utils = require "kong.clustering.utils"
local fields_validate = clustering_utils.fields_validate
local wrpc_proto = require("kong.tools.wrpc.proto")
local proto_new = wrpc_proto.new

local _M = {}

local pcall = pcall

-- DP and CP shares one list.
-- Always order from most to least preferred version.
local supported = {}

_M.supported = supported

local version_scheme = {
  [{
    "version",
  }] = "string",
  [{
    "description",
  }] = "string",
}

local function version_validate(version)
  return pcall(fields_validate, version, version_scheme)
end

local dp_service = proto_new()
local cp_service = proto_new()

_M.cp_service = cp_service
_M.dp_service = dp_service

-- dynamically register a cluster service
---@param name string name of the serivce
---@param versions table array of versions of the serivce, echo with fields like: { version = "v1", description = "example service" }
---@param service_init_dp function|nil callback to register wRPC services for dp if needed
---@param service_init_cp function|nil callback to register wRPC services for cp if needed
local function register(name, versions, service_init_dp, service_init_cp)
  if supported[name] then
    error("service name conflict or registered multiple times: " .. name)
  end

  if not versions[1] then
    error("at least one version should be provided for service " .. name)
  end

  for i, version in ipairs(versions) do
    local ok, err = version_validate(version)
    if not ok then
      error(name .. " service: #" .. i .. " of versions violates the scheme: " .. err)
    end
  end

  supported[name] = versions

  if service_init_dp then
    service_init_dp(_M.dp_service)
  end

  if service_init_cp then
    service_init_cp(_M.cp_service)
  end
end

_M.register = register

-- get all cluster services
---@return table services
function _M.get_services()
  return supported
end

function _M.init(conf)
  -- otherwise it would be recusive reference
  require "kong.clustering.services.negotiation".init(conf, dp_service, cp_service)

  -- by passing the function we avoid recusive reference
  require "kong.clustering.services.config".init(register)
end

return _M