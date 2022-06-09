local constants = require "kong.constants"
local clustering_utils = require "kong.clustering.utils"
-- currently they are the same. But it's possible for we to drop support for old version of DP but keep support of CP
local supported_services = require "kong.clustering.services.supported"
local asked_services = require "kong.clustering.services.supported"

local ngx_log = ngx.log
local ERR = ngx.ERR
local NOTICE = ngx.NOTICE
local _log_prefix = "[wrpc-clustering] "
local table_clear = require "table.clear"
local table_concat = table.concat
local lower = string.lower

local CLUSTERING_SYNC_STATUS = constants.CLUSTERING_SYNC_STATUS
local DECLARATIVE_EMPTY_CONFIG_HASH = constants.DECLARATIVE_EMPTY_CONFIG_HASH
local KONG_VERSION

-- it's so annoying that protobuf does not support map to array
local function wrap_services(service)
  local wrapped = {}
  for name, version in pairs(service) do
    wrapped[name] = {
      service = version
    }
  end

  return wrapped
end

local function unwrap_services(service)
  local unwrapped = {}
  for name, version in pairs(service) do
    unwrapped[name] = version.service
  end

  return unwrapped
end

local _M = {}

local function field_validate(tbl, field, typ)
  local v = tbl
  for _, ind in ipairs(field) do
    if type(v) ~= "table" then
      error("field cannot be indexed with " .. ind)
    end
    v = v[ind]
  end

  local compare_typ = typ
  if typ == "array" or typ == "object" then
    compare_typ = "table"
  end

  if type(v) ~= compare_typ then
    local field_name = table_concat(field, '.')
    error("field \"" .. field_name .. "\" must be of type " .. typ)
  end
end

local function verify_request(body)
  for field, typ in pairs{
    [{
      "node",
    }] = "object",
    [{
      "node", "type",
    }] = "string",
    [{
      "node", "version"
    }] = "string",
    [{
      "services_requested"
    }] = "array",
  } do
    field_validate(body, field, typ)
  end
end

local function verify_node_compatibility(client_node)
  if client_node.type ~= "KONG" then
    error(("unknown node type %q"):format(client_node.type), CLUSTERING_SYNC_STATUS.UNKNOWN)
  end

  if KONG_VERSION == nil then
    KONG_VERSION = kong.version
  end

  local ok, err, result = clustering_utils.check_kong_version_compatibility(KONG_VERSION, client_node.version)
  if not ok then
    error(err)
  end
  return result
end

local function negotiate_version(name, versions, known_versions)
  local versions_set = {}
  for _, v in ipairs(versions) do
    versions_set[lower(v.version)] = true
  end

  for _, v in ipairs(known_versions) do
    local version = lower(v.version)
    if versions_set[version] then
      return v
    end
  end

  return { name = name, description = "No valid version" }
end

local function negotiate_service(name, versions)
  name = lower(name)

  if type(versions) ~= "table" then
    error("invalid versions array for service " .. name)
  end

  local supported_service = supported_services[name]
  if not supported_service then
    return {
      description = "unknown service.",
    }
  end

  local service_response = negotiate_version(name, versions, supported_service)
  return service_response
end

local function log_negotiation_result(name, version)
  local ok = version.version ~= nil
  ngx_log(NOTICE, _log_prefix, "service ",
    (ok and "accepted" or "rejected"),
    ": \"", name, "\"",
    (ok and ", version: " .. version.version or ""),
    ", ", (ok and "description" or "reason"), ": ", version.description
  )
end

local function negotiate_services(services_requested)
  local services = {}

  for name, versions in pairs(services_requested) do
    if type(name) ~= "string" or type(versions) ~= "table" then
      error("malformed service requested " .. name)
    end

    local negotiated_version = negotiate_service(name, versions)
    services[name] = negotiated_version

    log_negotiation_result(name, negotiated_version)
  end

  return services
end


local function register_client(cluster_data_plane_purge_delay, id, client_node)
  local ok, err = kong.db.clustering_data_planes:upsert({ id = id, }, {
    last_seen = ngx.time(),
    config_hash = DECLARATIVE_EMPTY_CONFIG_HASH,
    hostname = client_node.hostname,
    ip = ngx.var.remote_addr,
    version = client_node.version,
    sync_status = client_node.sync_status,
  }, { ttl = cluster_data_plane_purge_delay })

  if not ok then
    ngx_log(ERR, _log_prefix, "unable to update clustering data plane status: ", err)
    return error(err)
  end
end

function _M.init_negotiation_server(service, conf)
  service:import("kong.services.negotiation.v1.negotiation")
  service:set_handler("NegotiationService.NegotiateServices", function(peer, nego_req)
    local ok, result = pcall(function()
      local dp_id = peer.id
      ngx_log(NOTICE, "negotiating services for DP: ", dp_id)
      local services_requested = unwrap_services(nego_req.services_requested)
      verify_request(nego_req)

      nego_req.node.sync_status = verify_node_compatibility(nego_req.node)
      local services = negotiate_services(services_requested)
      register_client(conf.cluster_data_plane_purge_delay, dp_id, nego_req.node)

      local nego_result = {
        services = services
      }

      return nego_result
    end)

    if not ok then
      ngx_log(ERR, _log_prefix, result)
      return { error_message = result }
    end

    return result
  end)
end

-- TODO: use event to notify other workers
-- Currently we assume only worker 0 cares about wRPC services
local negotiated_service
local function init_negotiated_service_tab()
  if not negotiated_service then
    negotiated_service = {}
  else
    table_clear(negotiated_service)
  end
end

local function set_negotiated_service(name, verison)
  negotiated_service[name] = verison
end

local negotiation_request

local function get_negotiation_request()
  if not negotiation_request then
    negotiation_request = {
      node = {
        type = "KONG",
        version = kong.version,
        hostname = kong.node.get_hostname(),
      },
      services_requested = wrap_services(asked_services),
    }
  end

  return negotiation_request
end

function _M.negotiate(peer)
  local response_data, err = peer:call_async("NegotiationService.NegotiateServices", get_negotiation_request())

  if not response_data then
    return nil, err
  end

  if response_data.error_message and not response_data.node then
    return nil, response_data.error_message
  end

  init_negotiated_service_tab()
  for name, version in pairs(response_data.services or {}) do
    log_negotiation_result(name, version)
    set_negotiated_service(name, version)
  end

  return response_data, nil
end

function _M.get_negotiated_service(name)
  local result = negotiated_service[name]
  if not result then
    return nil, "service not supported (and not requested)"
  end
  return result.version, result.description
end


function _M.init_negotiation_client(service)
  init_negotiated_service_tab()
  service:import("kong.services.negotiation.v1.negotiation")
end

return _M