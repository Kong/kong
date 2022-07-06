local constants = require "kong.constants"
local clustering_utils = require "kong.clustering.utils"
-- currently they are the same. But it's possible for we to drop support for old version of DP but keep support of CP
local supported_services = require "kong.clustering.services.supported"
local asked_services = require "kong.clustering.services.supported"
local table_clear = require "table.clear"

local time = ngx.time
local var = ngx.var
local log = ngx.log
local ERR = ngx.ERR
local NOTICE = ngx.NOTICE
local _log_prefix = "[wrpc-clustering] "
local table_concat = table.concat
local lower = string.lower
local pcall = pcall

-- an optimization. Used when a not modified empty table is needed.
local empty_table = {}

local pairs = pairs
local ipairs = ipairs
local type = type
local error = error

local CLUSTERING_SYNC_STATUS = constants.CLUSTERING_SYNC_STATUS
local DECLARATIVE_EMPTY_CONFIG_HASH = constants.DECLARATIVE_EMPTY_CONFIG_HASH

local NO_VALID_VERSION = { description = "no valid version", }
local UNKNOWN_SERVICE = { description = "unknown service", }

-- it's so annoying that protobuf does not support map to array
local function wrap_services(services)
  local wrapped, idx = {}, 0
  for name, versions in pairs(services or empty_table) do
    local wrapped_versions = {}
    idx = idx + 1
    wrapped[idx] = { name = name, versions = wrapped_versions, }

    for k, version in ipairs(versions) do
      wrapped_versions[k] = version.version
    end
  end

  return wrapped
end

local _M = {}

local function field_validate(tbl, field, typ)
  local v = tbl
  for i, ind in ipairs(field) do
    if type(v) ~= "table" then
      error("field '" .. table_concat(field, ".", 1, i - 1) .. "' cannot be indexed with " .. ind)
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

local request_scheme = {
  [{
    "node",
  }] = "object",
  [{
    "node", "type",
  }] = "string",
  [{
    "node", "version",
  }] = "string",
  [{
    "services_requested",
  }] = "array",
}

local function verify_request(body)
  for field, typ in pairs(request_scheme) do
    field_validate(body, field, typ)
  end
end

local function verify_node_compatibility(client_node)
  if client_node.type ~= "KONG" then
    error(("unknown node type %q"):format(client_node.type), CLUSTERING_SYNC_STATUS.UNKNOWN)
  end

  local ok, err, result = clustering_utils.check_kong_version_compatibility(kong.version, client_node.version)
  if not ok then
    error(err)
  end
  return result
end

local function negotiate_version(name, versions, known_versions)
  local versions_set = {}
  for _, version in ipairs(versions) do
    versions_set[lower(version)] = true
  end

  for _, v in ipairs(known_versions) do
    local version = lower(v.version)
    if versions_set[version] then
      return v
    end
  end

  return NO_VALID_VERSION
end

local function negotiate_service(name, versions)
  name = lower(name)

  if type(versions) ~= "table" then
    error("invalid versions array for service " .. name)
  end

  local supported_service = supported_services[name]
  if not supported_service then
    return UNKNOWN_SERVICE
  end

  return negotiate_version(name, versions, supported_service)
end

local function log_negotiation_result(name, version)
  if version.version ~= nil then
    log(NOTICE, "service accepted: \"", name, "\", version: ", version.version, ", description: ", version.description)

  else
    log(NOTICE, "service rejected: \"", name, "\", reason: ", version.description)
  end
end

local function negotiate_services(services_requested)
  local services = {}

  for idx, service in ipairs(services_requested) do
    local name = service.name
    if type(service) ~= "table" or type(name) ~= "string" then
      error("malformed service requested #" .. idx)
    end

    local negotiated_version = negotiate_service(name, service.versions)
    services[idx] = {
      name = name,
      negotiated_version = negotiated_version,
    }

    log_negotiation_result(name, negotiated_version)
  end

  return services
end


local function register_client(cluster_data_plane_purge_delay, id, client_node)
  local ok, err = kong.db.clustering_data_planes:upsert({ id = id, }, {
    last_seen = time(),
    config_hash = DECLARATIVE_EMPTY_CONFIG_HASH,
    hostname = client_node.hostname,
    ip = var.remote_addr,
    version = client_node.version,
    sync_status = client_node.sync_status,
  }, { ttl = cluster_data_plane_purge_delay })

  if not ok then
    log(ERR, _log_prefix, "unable to update clustering data plane status: ", err)
    return error(err)
  end
end

local function split_services(services)
  local accepted, accepted_n = {}, 0
  local rejected, rejected_n = {}, 0
  for _, service in ipairs(services or empty_table) do
    local tbl, idx
    local negotiated_version = service.negotiated_version
    if negotiated_version.version then
      accepted_n = accepted_n + 1
      tbl, idx = accepted, accepted_n
    else
      rejected_n = rejected_n + 1
      tbl, idx = rejected, rejected_n
    end

    tbl[idx] = {
      name = service.name,
      version = negotiated_version.version,
      message = negotiated_version.description,
    }
  end

  return accepted, rejected
end

local function info_to_service(info)
  return info.name, {
    version = info.version,
    description = info.message,
  }
end

local function merge_services(accepted, rejected)
  local services = {}
  for _, serivce in ipairs(accepted or empty_table) do
    local name, version = info_to_service(serivce)
    services[name] = version
  end

  for _, serivce in ipairs(rejected or empty_table) do
    local name, version = info_to_service(serivce)
    services[name] = version
  end

  return services
end

local cp_description

local function get_cp_description()
  if not cp_description then
    cp_description = {}
  end

  return cp_description
end

function _M.init_negotiation_server(service, conf)
  service:import("kong.services.negotiation.v1.negotiation")
  service:set_handler("NegotiationService.NegotiateServices", function(peer, nego_req)
    local ok, result = pcall(function()

      local dp_id = peer.id
      log(NOTICE, "negotiating services for DP: ", dp_id)
      verify_request(nego_req)

      nego_req.node.sync_status = verify_node_compatibility(nego_req.node)
      local services = negotiate_services(nego_req.services_requested)
      register_client(conf.cluster_data_plane_purge_delay, dp_id, nego_req.node)

      local accepted, rejected = split_services(services)

      local nego_result = {
        node = get_cp_description(),
        services_accepted = accepted,
        services_rejected = rejected,
      }

      return nego_result
    end)

    if not ok then
      log(ERR, _log_prefix, result)
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

local function set_negotiated_service(name, version)
  negotiated_service[name] = version
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
  local serivces = merge_services(response_data.services_accepted, response_data.services_rejected)
  for name, version in pairs(serivces) do
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

-- those funcitons are exported for tests
_M.split_services = split_services
_M.negotiate_services = negotiate_services

-- this function is just for tests!
function _M.__test_set_serivces(supported, asked)
  supported_services = supported or supported_services
  asked_services = asked or asked_services
end

return _M
