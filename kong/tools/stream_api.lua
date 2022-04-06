--- NOTE: this module implements a experimental RPC interface between the `http` and `stream`
-- subsystem plugins. It is intended for internal use only by Kong, and this interface
-- may changed or be removed in the future Kong releases once a better mechanism
-- for inter subsystem communication in OpenResty became available.

local lpack = require "lua_pack"

local kong = kong
local st_pack = lpack.pack
local st_unpack = lpack.unpack
local concat = table.concat
local assert = assert
local type = type
local tostring = tostring
local tcp = ngx.socket.tcp
local req_socket = ngx.req.socket
local exit = ngx.exit
local log = ngx.log
local ERR = ngx.ERR
local DEBUG = ngx.DEBUG
local WARN = ngx.WARN
local exiting = ngx.worker.exiting

local CLOSE = 444
local OK = 0


local PACK_F = "=CI"

-- unsigned char length
local MAX_KEY_LEN = 2^8 - 1

-- since the length is represented by an unsigned int we could theoretically
-- go up to 2^32, but that seems way beyond the amount of data that we should
-- expect to see exchanged over this interface
local MAX_DATA_LEN = 2^22 - 1

local HEADER_LEN = #st_pack(PACK_F, MAX_KEY_LEN, MAX_DATA_LEN)

local SOCKET_PATH = "unix:" .. ngx.config.prefix() .. "/stream_rpc.sock"

local stream_api = {}

local _handlers  = {}


-- # RPC format
--
-- RPC messages have a header and a body that are slightly different between
-- request and response.
--
-- ## requests
--
-- Requests have two components:
--  * key (string)
--  * payload (string)
--
-- The request header is made up of:
--
-- |   key len     | payload len  |
-- +---------------+--------------+
-- | unsigned char | unsigned int |
--
-- The header is followed by the request body, which is simply the request key
-- followed by the request payload (no separator).
--
-- ## responses
--
-- Responses have two components:
--   * status (integer)
--   * payload (string)
--
-- Responses have the same header length as requests, but with different
-- meanings implied by each field:
--
-- |   status      | body/payload len  |
-- +---------------+-------------------+
-- | unsigned char |   unsigned int    |
--
-- The response header is followed by the response body, which is equal to the
-- body/payload size in the header.


--- Compose and send a stream API message.
--
-- Returns truth-y on success or `nil`, and an error string on failure.
--
-- @tparam  tcpsock       sock
-- @tparam  string|number key_or_status
-- @tparam  string        data
-- @treturn boolean       ok
-- @treturn string|nil    error
local function send(sock, key_or_status, data)
  local key
  local key_len

  local typ = type(key_or_status)

  if typ == "number" then
    -- we're sending a response, so the (numerical) status is simply encoded as
    -- part of the header
    key = ""
    key_len = key_or_status

  elseif typ == "string" then
    -- we're sending a request, so the key length is included in the header,
    -- while the key itself is part of the body
    key = key_or_status
    key_len = #key_or_status

    if key_len == 0 then
      return nil, "empty key"
    end

  else
    return nil, "invalid type for key/status: " .. typ
  end

  if key_len > MAX_KEY_LEN then
    return nil, "max key/status size exceeded"
  end

  local data_len = #data
  if data_len > MAX_DATA_LEN then
    return nil, "max data size exceeded"
  end

  local header = st_pack(PACK_F, key_len, data_len)
  local msg = header .. key .. data

  return sock:send(msg)
end


--- Send a stream API response.
--
-- The connection is closed if send() fails or when returning a non-zero
-- status code.
--
-- @tparam tcpsock sock
-- @tparam integer status
-- @tparam string  msg
local function send_response(sock, status, msg)
  local sent, err = send(sock, status, msg)
  if not sent then
    log(ERR, "failed sending response: ", err)
    return exit(CLOSE)
  end

  if status ~= 0 then
    log(WARN, "closing connection due to non-zero status code")
    return exit(CLOSE)
  end

  return true
end


--- Read the request/response header.
--
-- @tparam tcpsock sock
--
-- @treturn number|nil key_len
-- @treturn string|nil data_len
-- @treturn nil|string error
local function recv_header(sock)
  local header, err = sock:receive(HEADER_LEN)
  if not header then
    return nil, nil, err
  end

  local pos, key_len, data_len = st_unpack(header, PACK_F)

  -- this probably shouldn't happen
  if not (pos == (HEADER_LEN + 1) and key_len and data_len) then
    return nil, nil, "invalid header/data received"
  end

  return key_len, data_len
end

--- Receive a stream API request from a downstream client.
--
-- @tparam tcpsock sock
--
-- @treturn string|nil handler request handler name (`nil` in case of failure)
-- @treturn string|nil body    request payload (`nil` in case of failure)
-- @treturn nil|string error   an error string
local function recv_request(sock)
  local key_len, data_len, err = recv_header(sock)
  if not key_len then
    return nil, nil, err
  end

  -- requests have the key size packed in the header with the actual key
  -- at the head of the remaining data
  local body_len = key_len + data_len

  local body
  body, err = sock:receive(body_len)
  if not body then
    -- need the caller to be able to differentiate between a timeout
    -- while reading the header (normal) vs a timeout while reading the
    -- request payload (not normal)
    err = err == "timeout"
          and "timeout while reading request body"
          or err
    return nil, nil, err
  end

  return body:sub(1, key_len), body:sub(key_len + 1)
end


--- Receive a stream API response from the server.
--
-- @tparam tcpsock sock
--
-- @treturn number|nil ok     response status code (`nil` in case of socket error)
-- @treturn string|nil body   response payload (`nil` in case of socket error)
-- @treturn nil|string error  an error string, returned for protocol or socket I/O failures
local function recv_response(sock)
  local status, body_len, err = recv_header(sock)
  if not status then
    return nil, nil, err
  end

  local body
  body, err = sock:receive(body_len)
  if not body then
    return nil, nil, err
  end

  return status, body
end


function stream_api.load_handlers()
  local utils = require "kong.tools.utils"

  for plugin_name in pairs(kong.configuration.loaded_plugins) do
    local loaded, custom_endpoints = utils.load_module_if_exists("kong.plugins." .. plugin_name .. ".api")
    if loaded and custom_endpoints._stream then
      log(DEBUG, "Register stream api for plugin: ", plugin_name)
      _handlers[plugin_name] = custom_endpoints._stream
      custom_endpoints._stream = nil
    end
  end
end


--- Send a stream API request.
--
-- @tparam  string       key          API handler key/name
-- @tparam  string       data         request payload
-- @tparam  string|nil   socket_path  optional path to an alternate unix socket
--
-- @treturn string|nil   response
-- @treturn nil|string   error
function stream_api.request(key, data, socket_path)
  if type(key) ~= "string" or type(data) ~= "string" then
    return nil, "key and data must be strings"
  end

  local sock = assert(tcp())

  -- connect/send should always be fast here unless NGINX is really struggling,
  -- but read might be slow depending on how long our handler takes to execute
  sock:settimeouts(1000, 1000, 10000)

  socket_path = socket_path or SOCKET_PATH

  local ok, err = sock:connect(socket_path)
  if not ok then
    return nil, "opening internal RPC socket: " .. tostring(err)
  end

  ok, err = send(sock, key, data)
  if not ok then
    return nil, "sending stream-api request: " .. tostring(err)
  end

  local status, res
  status, res, err = recv_response(sock)
  if not status then
    return nil, "retrieving stream-api response: " .. tostring(err)
  end

  if status ~= 0 then
    return nil, "stream-api err: " .. tostring(res or "unknown")
  end

  ok, err = sock:setkeepalive()
  if not ok then
    log(WARN, "failed setting keepalive for request sock: ", err)
  end

  return res
end


function stream_api.handle()
  local sock = assert(req_socket())

  -- keepalive is assumed here
  while not exiting() do
    local key, data, err = recv_request(sock)

    if not key then
      if err == "timeout" then
        return exit(OK)
      end

      log(ERR, "failed receiving request: ", tostring(err))
      return exit(CLOSE)
    end

    local f = _handlers[key]
    if not f then
      return send_response(sock, 1, "no handler")
    end

    local ok, res
    ok, res, err = pcall(f, data)
    if not ok then
      return send_response(sock, 2, "handler exception: " .. tostring(res))

    elseif not res then
      return send_response(sock, 2, "handler error: " .. tostring(err))
    end

    if type(res) == "table" then
      res = concat(res)
    end

    if type(res) ~= "string" then
      log(ERR, "stream_api handler ", key, " response is not a string")

      return send_response(sock, 3, "invalid handler response type")
    end

    if #res > MAX_DATA_LEN then
      log(ERR, "stream_api handler ", key,
                   " response size is > ", MAX_DATA_LEN, " (", #res, ")")

      return send_response(sock, 4, "invalid handler response size")
    end

    if not send_response(sock, 0, res) then
      return
    end
  end

  return exit(OK)
end

stream_api.MAX_PAYLOAD_SIZE = MAX_DATA_LEN

return stream_api
