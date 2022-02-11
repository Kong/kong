
local cjson = require "cjson.safe"
local pl_file = require "pl.file"

local constants = require "kong.constants"
local clustering_utils = require "kong.clustering.utils"

local ngx_log = ngx.log
local ngx_DEBUG = ngx.DEBUG
local ngx_INFO = ngx.INFO
local ngx_NOTICE = ngx.NOTICE
local ngx_WARN = ngx.WARN
local ngx_ERR = ngx.ERR
local ngx_OK = ngx.OK
local ngx_CLOSE = ngx.HTTP_CLOSE
local _log_prefix = "[version-negotiation] "

local CLUSTERING_SYNC_STATUS = constants.CLUSTERING_SYNC_STATUS


local _M = {}


local function get_body()
  ngx.req.read_body()
  local body = ngx.req.get_body_data()
  if body then
    return body
  end

  local fname = ngx.req.get_body_file()
  if fname then
    return pl_file.read(fname)
  end

  return ""
end

local function response(status, body)
  ngx.status = status

  if type(body) == "table" then
    ngx.header["Content-Type"] = "application/json"
    body = cjson.encode(body)
  end

  ngx.say(body)
  return ngx.exit(status)
end

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

local all_known_services = {
  ["protocol"] = {
    ["json"] = { message = "current" },
    ["wrpc"] = { message = "beta" },
  },
}

local function check_node_compatibility(client_node)
  if client_node.type ~= "KONG" then
    return nil, ("unknown node type %q"):format(client_node.type), CLUSTERING_SYNC_STATUS.UNKNOWN
  end

  local ok, msg, status = clustering_utils.check_kong_version_compatibility(client_node.version)
  if not ok then
    return ok, msg, status
  end

  return true, nil, CLUSTERING_SYNC_STATUS.NORMAL
end

local function do_negotiation(req_body)
  local services_accepted = {}
  local services_rejected = {}

  for _, req_service in ipairs(req_body.services_requested) do
    if type(req_service) ~= "table" or type(req_service.name) ~= "string" then
      goto continue
    end

    local name = req_service.name

    if type(req_service.versions) ~= "table" then
      table.insert(services_rejected, {
        name = name,
        message = "invalid \"versions\" table.",
      })
      goto continue
    end

    local known_service = all_known_services[name]
    if not known_service then
      table.insert(services_rejected, {
        name = name,
        message = "unknown service.",
      })
      goto continue
    end

    for j, version in ipairs(req_service.versions) do
      if type(version) ~= "string" then
        table.insert(services_rejected, {
          name = name,
          message = string.format("invalid version at position #d", j),
        })
        goto continue
      end

      local known_version = known_service[version]
      if known_version then
        table.insert(services_accepted, {
          name = name,
          version = version,
          message = known_version.message,
        })
        break
      end
    end

    ::continue::
  end

  return {
    node = node_info(),
    services_accepted = services_accepted,
    services_rejected = services_rejected,
  }
end


local function register_client(conf, client_node, services_accepted)
  local client_services = {}
  for _, service in ipairs(services_accepted) do
    client_services[service.name] = service.version
  end

  local ok, err = kong.db.clustering_data_planes:upsert({ id = client_node.id, }, {
    last_seen = ngx.time(),
    config_hash = "0123456789ABCDEF0123456789ABCDEF",
    hostname = client_node.hostname,
    ip = ngx.var.realip_remote_addr or ngx.var.remote_addr,
    version = client_node.version,
    sync_status = client_node.sync_status,
  }, { ttl = conf.cluster_data_plane_purge_delay })

  if not ok then
    ngx_log(ngx_ERR, _log_prefix, "unable to update clustering data plane status: ", err)
    return nil, err
  end

  return true
end


function _M.serve_version_handshake(conf)
  local body_in = cjson.decode(get_body())
  if not body_in then
    return response(400, { message = "Not valid JSON data" })
  end

  local ok, err = verify_request(body_in)
  if not ok then
    return response(400, { message = err })
  end

  ok, err, body_in.node.sync_status = check_node_compatibility(body_in.node)
  if not ok then
    return response(400, { message = err })
  end

  local body_out = do_negotiation(body_in)

  ok, err = register_client(conf, body_in.node, body_out.services_accepted)
  if not ok then
    return response(400, { message = err })
  end


  return response(200, body_out)
end

return _M
