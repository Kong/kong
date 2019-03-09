-- ALF implementation for ngx_lua/Kong
-- ALF version: 1.1.0
-- @version 2.0.0
-- @see https://github.com/Kong/galileo-agent-spec
--
-- Incompatibilities with ALF 1.1 and important notes
-- ==================================================
-- * The following fields cannot be retrieved as of ngx_lua 0.10.2:
--     * response.statusText
--     * response.headersSize
--
-- * Kong can modify the request/response due to its nature, hence,
--   we distinguish the original req/res from the current req/res
--     * request.headersSize will be the size of the _original_ headers
--       received by Kong
--     * request.headers will contain the _current_ headers
--     * response.headers will contain the _current_ headers
--
-- * bodyCaptured properties are determined using HTTP headers
-- * timings.blocked is ignored
-- * timings.connect is ignored

local cjson = require "cjson.safe"
local resp_get_headers = ngx.resp.get_headers
local req_start_time = ngx.req.start_time
local req_get_method = ngx.req.get_method
local req_get_headers = ngx.req.get_headers
local req_get_uri_args = ngx.req.get_uri_args
local encode_base64 = ngx.encode_base64
local http_version = ngx.req.http_version
local setmetatable = setmetatable
local tonumber = tonumber
local os_date = os.date
local pairs = pairs
local type = type
local gsub = string.gsub
local fmt = string.format

local _M = {
  _VERSION = "2.0.0",
  _ALF_VERSION = "1.1.0",
  _ALF_CREATOR = "brain-agent-kong"
}

local _mt = {
  __index = _M
}

function _M.new(log_bodies, server_addr)
  local alf = {
    server_addr = server_addr,
    log_bodies = log_bodies,
    entries = {}
  }

  return setmetatable(alf, _mt)
end

-- Convert a table such as returned by ngx.*.get_headers()
-- to integer-indexed arrays.
local function hash_to_array(t)
  local arr = setmetatable({}, cjson.empty_array_mt)
  for k, v in pairs(t) do
    if type(v) == "table" then
      for i = 1, #v do
        arr[#arr+1] = {name = k, value = v[i]}
      end
    else
      arr[#arr+1] = {name = k, value = v}
    end
  end

  return arr
end

-- Calculate an approximation of header size (it doesn't calculate white
-- space that may be sorrounding values, other than that it's accurate)
local function calculate_headers_size(request_line, headers)
  local size = 0
  for k, v in pairs(headers) do
    if type(v) == "table" then
      for _, y in ipairs(v) do
        size = size + #k + 2 + #tostring(y) + 2 --First 2 is semicolon + space
      end
    else
      size = size + #k + 2 + #tostring(v) + 2 --First 2 is semicolon + space
    end
  end
  return #request_line + 2 + size + 2 -- 2 it's \r\n, 4 it's trailing \r\n\r\n
end

local function get_header(t, name, default)
  local v = t[name]
  if not v then
    return default
  elseif type(v) == "table" then
    return v[#v]
  end
  return v
end

--- Add an entry to the ALF's `entries`
-- @param[type=table] _ngx The ngx table, containing .var and .ctx
-- @param[type=string] req_body_str The request body
-- @param[type=string] res_body_str The response body
-- @treturn table The entry created
-- @treturn number The new size of the `entries` array
function _M:add_entry(_ngx, req_body_str, resp_body_str)
  if not self.entries then
    return nil, "no entries table"
  elseif not _ngx then
    return nil, "arg #1 (_ngx) must be given"
  elseif req_body_str ~= nil and type(req_body_str) ~= "string" then
    return nil, "arg #2 (req_body_str) must be a string"
  elseif resp_body_str ~= nil and type(resp_body_str) ~= "string" then
    return nil, "arg #3 (resp_body_str) must be a string"
  end

  -- retrieval
  local var = _ngx.var
  local ctx = _ngx.ctx
  local http_version = "HTTP/" .. http_version()
  local method = req_get_method()
  local request_headers = req_get_headers()
  local request_content_len = get_header(request_headers, "content-length", 0)
  local request_transfer_encoding = get_header(request_headers, "transfer-encoding")
  local request_content_type = get_header(request_headers, "content-type",
                                          "application/octet-stream")

  -- if log_bodies is false, we don't want to still call
  -- ngx.req.read_body() anyways, hence we rely on RFC 2616
  -- to determine if the request seems to have a body.
  local req_has_body = tonumber(request_content_len) > 0
                       or request_transfer_encoding ~= nil
                       or request_content_type == "multipart/byteranges"

  local resp_headers = resp_get_headers()
  local resp_content_len = get_header(resp_headers, "content-length", 0)
  local resp_transfer_encoding = get_header(resp_headers, "transfer-encoding")
  local resp_content_type = get_header(resp_headers, "content-type",
                            "application/octet-stream")

  local resp_has_body = tonumber(resp_content_len) > 0
                        or resp_transfer_encoding ~= nil
                        or resp_content_type == "multipart/byteranges"

  -- request.postData. we don't check has_body here, but rather
  -- stick to what the request really contains, since it was
  -- already read anyways.
  local post_data, response_content
  local req_body_size, resp_body_size

  if self.log_bodies then
    if req_body_str then
      req_body_size = #req_body_str
      post_data = {
        text = encode_base64(req_body_str),
        encoding = "base64",
        mimeType = request_content_type
      }
    end

    if resp_body_str then
      resp_body_size = #resp_body_str
      response_content = {
        text = encode_base64(resp_body_str),
        encoding = "base64",
        mimeType = resp_content_type
      }
    end
  end

  if not req_body_size then
    req_body_size = tonumber(request_content_len) or 0
  end

  if not resp_body_size then
    resp_body_size = tonumber(resp_content_len) or 0
  end

  -- timings
  local send_t = ctx.KONG_PROXY_LATENCY or 0
  local wait_t = ctx.KONG_WAITING_TIME or 0
  local receive_t = ctx.KONG_RECEIVE_TIME or 0

  local idx = #self.entries + 1

  self.entries[idx] = {
    time = send_t + wait_t + receive_t,
    startedDateTime = os_date("!%Y-%m-%dT%TZ", req_start_time()),
    serverIPAddress = self.server_addr,
    clientIPAddress = var.remote_addr,
    request = {
      httpVersion = http_version,
      method = method,
      url = var.scheme .. "://" .. var.host .. var.request_uri,
      queryString = hash_to_array(req_get_uri_args()),
      headers = hash_to_array(request_headers),
      headersSize = calculate_headers_size(
                      fmt("%s %s %s", method, var.request_uri, http_version),
                      request_headers),
      postData = post_data,
      bodyCaptured = req_has_body,
      bodySize = req_body_size,
    },
    response = {
      status = _ngx.status,
      statusText = "",
      httpVersion = http_version,
      headers = hash_to_array(resp_headers),
      content = response_content,
      headersSize = 0,
      bodyCaptured = resp_has_body,
      bodySize = resp_body_size
    },
    timings = {
      send = send_t,
      wait = wait_t,
      receive = receive_t
    },
    _kong = {
      service = ctx.service,
      route = ctx.route,
      workspaces = ctx.log_request_workspaces,
    },
  }

  return self.entries[idx], idx
end

local buf = {
  version = _M._ALF_VERSION,
  serviceToken = nil,
  environment = nil,
  har = {
    log = {
      creator = {
        name = _M._ALF_CREATOR,
        version = _M._VERSION
      },
      entries = nil
    }
  }
}

local _alf_max_size = 20 * 2^20

--- Encode the current ALF to JSON
-- @param[type=string] service_token The ALF `serviceToken`
-- @param[type=string] environment (optional) The ALF `environment`
-- @treturn string The ALF, JSON encoded
function _M:serialize(service_token, environment)
  if not self.entries then
    return nil, "no entries table"
  elseif type(service_token) ~= "string" then
    return nil, "arg #1 (service_token) must be a string"
  elseif environment ~= nil and type(environment) ~= "string" then
    return nil, "arg #2 (environment) must be a string"
  end

  buf.serviceToken = service_token
  buf.environment = environment
  buf.har.log.entries = self.entries

  local json = cjson.encode(buf)
  if #json > _alf_max_size then
    return nil, "ALF too large (> 20MB)"
  end

  return gsub(json, "\\/", "/"), #self.entries
end

--- Empty the ALF
function _M:reset()
  self.entries = {}
end

return _M

