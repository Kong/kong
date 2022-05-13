local cjson = require "cjson.safe"

local constants = require "kong.constants"
local clustering_utils = require "kong.clustering.utils"

local str_lower = string.lower
local table_insert = table.insert
local ngx = ngx
local ngx_log = ngx.log
local ngx_ERR = ngx.ERR
local ngx_DEBUG = ngx.DEBUG
local _log_prefix = "[version-negotiation] "

local KONG_VERSION
local CLUSTERING_SYNC_STATUS = constants.CLUSTERING_SYNC_STATUS
local DECLARATIVE_EMPTY_CONFIG_HASH = constants.DECLARATIVE_EMPTY_CONFIG_HASH


local _M = {}

local function verify_request(body)
  if type(body.node) ~= "table" then
    return false, "field \"node\" must be an object."
  end

  if type(body.node.id) ~= "string" then
    return false, "field \"node.id\" must be a string."
  end

  if type(body.node.type) ~= "string" then
    return false, "field \"node.type\" must be a string."
  end

  if type(body.node.version) ~= "string" then
    return false, "field \"node.version\" must be a string."
  end

  if type(body.services_requested) ~= "table" then
    return false, "field \"services_requested\" must be an array."
  end

  return true
end


local function node_info()
  return {
    id = kong.node.get_id()
  }
end

local function cp_priority(name, req_versions, known_versions)
  local versions_set = {}
  for _, version in ipairs(req_versions) do
    versions_set[str_lower(version)] = true
  end

  for _, v in ipairs(known_versions) do
    local version = str_lower(v.version)
    if versions_set[version] then
      return true, {
        name = name,
        version = version,
        message = v.message,
      }
    end
  end

  return false, { name = name, message = "No valid version" }
end

local all_known_services = require "kong.clustering.version_negotiation.services_known"

local function check_node_compatibility(client_node)
  if client_node.type ~= "KONG" then
    return nil, ("unknown node type %q"):format(client_node.type), CLUSTERING_SYNC_STATUS.UNKNOWN
  end

  if KONG_VERSION == nil then
    KONG_VERSION = kong.version
  end

  return clustering_utils.check_kong_version_compatibility(KONG_VERSION, client_node.version)
end

local function do_negotiation(req_body)
  local services_accepted = {}
  local services_rejected = {}
  local accepted_map = {}

  for i, req_service in ipairs(req_body.services_requested) do
    if type(req_service) ~= "table" or type(req_service.name) ~= "string" then
      return nil, "malformed service requested item #" .. tostring(i)
    end

    local name = str_lower(req_service.name)

    if type(req_service.versions) ~= "table" then
      return nil, "invalid versions array for service " .. req_service.name
    end

    local known_service = all_known_services[name]
    if not known_service then
      table_insert(services_rejected, {
        name = name,
        message = "unknown service.",
      })
      goto continue
    end

    local ok, service_response = cp_priority(name, req_service.versions, known_service)
    if ok then
      ngx_log(ngx_DEBUG, _log_prefix,
        "accepted: \"" .. service_response.name ..
        "\", version \"" .. service_response.version ..
        "\": ".. service_response.message)
      table_insert(services_accepted, service_response)
      accepted_map[service_response.name] = service_response.version
    else

      ngx_log(ngx_DEBUG, _log_prefix,
        "rejected: \"" .. service_response.name ..
        "\": " .. service_response.message)
      table_insert(services_rejected, service_response)
    end

    ::continue::
  end

  return {
    node = node_info(),
    services_accepted = services_accepted,
    services_rejected = services_rejected,
    accepted_map = accepted_map,
  }
end


local function register_client(conf, client_node)
  local ok, err = kong.db.clustering_data_planes:upsert({ id = client_node.id, }, {
    last_seen = ngx.time(),
    config_hash = DECLARATIVE_EMPTY_CONFIG_HASH,
    hostname = client_node.hostname,
    ip = ngx.var.remote_addr,
    version = client_node.version,
    sync_status = client_node.sync_status,
  }, { ttl = conf.cluster_data_plane_purge_delay })

  if not ok then
    ngx_log(ngx_ERR, _log_prefix, "unable to update clustering data plane status: ", err)
    return nil, err
  end

  return true
end


function _M.add_negotiation_service(service, conf)
  service:add("kong.services.negotiation.v1.negotiation")
  service:set_handler("NegotiationService.NegotiateServices", function(peer, data)
    local body_in = data
    local ok, err = verify_request(body_in)
    if not ok then
      ngx_log(ngx_ERR, _log_prefix, err)
      return {message = err}
    end

    ok, err, body_in.node.sync_status = check_node_compatibility(body_in.node)
    if not ok then
      ngx_log(ngx_ERR, _log_prefix, err)
      return {message = err}
    end

    local body_out
    body_out, err = do_negotiation(body_in)
    if not body_out then
      ngx_log(ngx_ERR, _log_prefix, err)
      return {message = err}
    end

    peer.services_accepted = body_out.accepted_map

    ok, err = register_client(conf, body_in.node)
    if not ok then
      ngx_log(ngx_ERR, _log_prefix, err)
      return { message = err }
    end

    return body_out
  end)
end

function _M.get_service_override(conf)
  if conf.cached_service_override then
    return conf.cached_service_override
  end

  local override_sets = {}
  for _, over in ipairs(conf.cluster_services_override or {}) do
    local srv, vers = over:match("^([^.]+)%.([^.]+)$")
    override_sets[srv] = override_sets[srv] or {}
    override_sets[srv][vers] = true
  end

  conf.cached_service_override = override_sets
  return override_sets
end

local function set_to_list(set)
  local list = {}

  for k in pairs(set) do
    table_insert(set, k)
  end

  return list
end

function _M.get_request_body(conf, services_requested)
  local override_sets = _M.get_service_override(conf)

  services_requested = services_requested or require "kong.clustering.version_negotiation.services_requested"
  for _, srv in ipairs(services_requested) do
    local override_service = override_sets[srv.name]
    if override_service then
      srv.versions = set_to_list(override_service)
    end
  end

  return {
    node = {
      id = kong.node.get_id(),
      type = "KONG",
      version = kong.version,
      hostname = kong.node.get_hostname(),
    },
    services_requested = services_requested,
  }
end

function _M.call_wrpc_negotiation(peer, conf)
  local response_data, err = peer:call_wait("NegotiationService.NegotiateServices", _M.get_request_body(conf))
  if response_data[1] then
    response_data = response_data[1]
  end
  if not response_data then
    return nil, err
  end

  if response_data.message and not response_data.node then
    return nil, response_data.message
  end

  for _, service in ipairs(response_data.services_accepted or {}) do
    ngx_log(ngx.NOTICE, _log_prefix, ("accepted: %q, version %q: %q"):format(
      service.name, service.version, service.message or ""))

    _M.set_negotiated_service(service.name, service.version, service.message)
  end

  for _, service in ipairs(response_data.services_rejected or {}) do
    ngx_log(ngx.NOTICE, _log_prefix, ("rejected: %q: %q"):format(service.name, service.message))
    _M.set_negotiated_service(service.name, nil, service.message)
  end

  return response_data, nil
end


local kong_shm = ngx.shared.kong
local SERVICE_KEY_PREFIX = "version_negotiation:service:"


function _M.set_negotiated_service(name, version, message)
  name = str_lower(name)
  version = version and str_lower(version)
  local ok, err = kong_shm:set(SERVICE_KEY_PREFIX .. name, cjson.encode{
    version = version,
    message = message,
  })
  if not ok then
    ngx_log(ngx_ERR, _log_prefix, string.format("couldn't store negotiated service %q (%q): %s",
      name, version, err))
  end
end

--- result of an already-negotiated service.
--- If it was accepted returns version, message.
--- If it was rejected returns nil, message.
--- If wasn't requested returns nil, nil
function _M.get_negotiated_service(name)
  name = str_lower(name)
  local val, err = kong_shm:get(SERVICE_KEY_PREFIX .. name)
  if not val then
    return nil, err
  end

  val = cjson.decode(val)
  if not val then
    return nil, "corrupted dictionary"
  end

  return val.version, val.message
end

return _M
