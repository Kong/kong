local utils      = require "kong.tools.utils"
local cjson_safe = require "cjson.safe"
local cjson      = require "cjson"
local ws_server  = require "resty.websocket.server"
local pl_stringx = require "pl.stringx"


local OCSP_RESPONSE_GOOD = [[
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
]]
local OCSP_RESPONSE_REVOKED = [[
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
]]


local kong = {
  table = require("kong.pdk.table").new()
}

local ocsp_status = "good"

local function parse_multipart_form_params(body, content_type)
  if not content_type then
    return nil, 'missing content-type'
  end

  local m, err = ngx.re.match(content_type, "boundary=(.+)", "oj")
  if not m or not m[1] or err then
    return nil, "could not find boundary in content type " .. content_type ..
                "error: " .. tostring(err)
  end

  local boundary    = m[1]
  local parts_split = utils.split(body, '--' .. boundary)
  local params      = {}
  local part, from, to, part_value, part_name, part_headers, first_header
  for i = 1, #parts_split do
    part = pl_stringx.strip(parts_split[i])

    if part ~= '' and part ~= '--' then
      from, to, err = ngx.re.find(part, '^\\r$', 'ojm')
      if err or (not from and not to) then
        return nil, nil, "could not find part body. Error: " .. tostring(err)
      end

      part_value   = part:sub(to + 2, #part) -- +2: trim leading line jump
      part_headers = part:sub(1, from - 1)
      first_header = utils.split(part_headers, '\\n')[1]
      if pl_stringx.startswith(first_header:lower(), "content-disposition") then
        local m, err = ngx.re.match(first_header, 'name="(.*?)"', "oj")

        if err or not m or not m[1] then
          return nil, "could not parse part name. Error: " .. tostring(err)
        end

        part_name = m[1]
      else
        return nil, "could not find part name in: " .. part_headers
      end

      params[part_name] = part_value
    end
  end

  return params
end


local function send_text_response(text, content_type, headers)
  headers       = headers or {}
  content_type  = content_type or "text/plain"

  text = ngx.req.get_method() == "HEAD" and "" or tostring(text)

  ngx.header["X-Powered-By"]   = "mock_upstream"
  ngx.header["Content-Length"] = #text + 1
  ngx.header["Content-Type"]   = content_type

  for header,value in pairs(headers) do
    if type(value) == "table" then
      ngx.header[header] = table.concat(value, ", ")
    else
      ngx.header[header] = value
    end
  end

  return ngx.say(text)
end


local function filter_access_by_method(method)
  if ngx.req.get_method() ~= method then
    ngx.status = ngx.HTTP_NOT_ALLOWED
    send_text_response("Method not allowed for the requested URL")
    return ngx.exit(ngx.OK)
  end
end


local function find_http_credentials(authorization_header)
  if not authorization_header then
    return
  end

  local iterator, iter_err = ngx.re.gmatch(authorization_header,
                                           "\\s*[Bb]asic\\s*(.+)")
  if not iterator then
    ngx.log(ngx.ERR, iter_err)
    return
  end

  local m, err = iterator()

  if err then
    ngx.log(ngx.ERR, err)
    return
  end

  if m and m[1] then
    local decoded_basic = ngx.decode_base64(m[1])

    if decoded_basic then
      local user_pass = utils.split(decoded_basic, ":")
      return user_pass[1], user_pass[2]
    end
  end
end


local function filter_access_by_basic_auth(expected_username,
                                           expected_password)
   local headers = ngx.req.get_headers()

   local username, password =
   find_http_credentials(headers["proxy-authorization"])

   if not username then
     username, password =
     find_http_credentials(headers["authorization"])
   end

   if username ~= expected_username or password ~= expected_password then
     ngx.header["WWW-Authenticate"] = "mock_upstream"
     ngx.header["X-Powered-By"]     = "mock_upstream"
     return ngx.exit(ngx.HTTP_UNAUTHORIZED)
   end
end


local function get_ngx_vars()
  local var = ngx.var
  return {
    uri                = var.uri,
    host               = var.host,
    hostname           = var.hostname,
    https              = var.https,
    scheme             = var.scheme,
    is_args            = var.is_args,
    server_addr        = var.server_addr,
    server_port        = var.server_port,
    server_name        = var.server_name,
    server_protocol    = var.server_protocol,
    remote_addr        = var.remote_addr,
    remote_port        = var.remote_port,
    realip_remote_addr = var.realip_remote_addr,
    realip_remote_port = var.realip_remote_port,
    binary_remote_addr = var.binary_remote_addr,
    request            = var.request,
    request_uri        = var.request_uri,
    request_time       = var.request_time,
    request_length     = var.request_length,
    request_method     = var.request_method,
    bytes_received     = var.bytes_received,
    ssl_server_name    = var.ssl_server_name or "no SNI",
  }
end


local function get_body_data()
  local req   = ngx.req

  req.read_body()
  local data  = req.get_body_data()
  if data then
    return data
  end

  local file_path = req.get_body_file()
  if file_path then
    local file = io.open(file_path, "r")
    data       = file:read("*all")
    file:close()
    return data
  end

  return ""
end

local function get_post_data(content_type)
  local text   = get_body_data()
  local kind   = "unknown"
  local params = cjson_safe.null
  local err

  if type(content_type) == "string" then
    if content_type:find("application/x-www-form-urlencoded", nil, true) then

      kind        = "form"
      params, err = ngx.req.get_post_args()

    elseif content_type:find("multipart/form-data", nil, true) then
      kind        = "multipart-form"
      params, err = parse_multipart_form_params(text, content_type)

    elseif content_type:find("application/json", nil, true) then
      kind        = "json"
      params, err = cjson_safe.decode(text)
    end

    params = params or cjson_safe.null

    if err then
      kind = kind .. " (error)"
      err  = tostring(err)
    end
  end

  return { text = text, kind = kind, params = params, error = err }
end


local function get_default_json_response()
  local headers = ngx.req.get_headers(0)
  local vars    = get_ngx_vars()

  return {
    headers   = headers,
    post_data = get_post_data(headers["Content-Type"]),
    url       = ("%s://%s:%s%s"):format(vars.scheme, vars.host,
                                        vars.server_port, vars.request_uri),
    uri_args  = ngx.req.get_uri_args(),
    vars      = vars,
  }
end


local function send_default_json_response(extra_fields, response_headers)
  local tbl = kong.table.merge(get_default_json_response(), extra_fields)
  return send_text_response(cjson.encode(tbl),
                            "application/json", response_headers)
end


local function serve_web_sockets()
  local wb, err = ws_server:new({
    timeout         = 5000,
    max_payload_len = 65535,
  })

  if not wb then
    ngx.log(ngx.ERR, "failed to open websocket: ", err)
    return ngx.exit(444)
  end

  while true do
    local data, typ, err = wb:recv_frame()
    if wb.fatal then
      ngx.log(ngx.ERR, "failed to receive frame: ", err)
      return ngx.exit(444)
    end

    if data then
      if typ == "close" then
        break
      end

      if typ == "ping" then
        local bytes, err = wb:send_pong(data)
        if not bytes then
          ngx.log(ngx.ERR, "failed to send pong: ", err)
          return ngx.exit(444)
        end

      elseif typ == "pong" then
        ngx.log(ngx.INFO, "client ponged")

      elseif typ == "text" then
        local bytes, err = wb:send_text(data)
        if not bytes then
          ngx.log(ngx.ERR, "failed to send text: ", err)
          return ngx.exit(444)
        end
      end

    else
      local bytes, err = wb:send_ping()
      if not bytes then
        ngx.log(ngx.ERR, "failed to send ping: ", err)
        return ngx.exit(444)
      end
    end
  end

  wb:send_close()
end


local function get_logger()
  local logger = ngx.shared.kong_mock_upstream_loggers
  if not logger then
    error("missing 'kong_mock_upstream_loggers' shm declaration")
  end

  return logger
end


local function store_log(logname)
  ngx.req.read_body()

  local raw_entries = ngx.req.get_body_data()
  local logger = get_logger()

  local entries = cjson.decode(raw_entries)
  if #entries == 0 then
    -- backwards-compatibility for `conf.queue_size == 1`
    entries = { entries }
  end

  local log_req_headers = ngx.req.get_headers()

  for i = 1, #entries do
    local store = {
      entry = entries[i],
      log_req_headers = log_req_headers,
    }

    assert(logger:rpush(logname, cjson.encode(store)))
    assert(logger:incr(logname .. "|count", 1, 0))
  end

  ngx.status = 200
end


local function retrieve_log(logname)
  local logger = get_logger()
  local len = logger:llen(logname)
  local entries = {}

  for i = 1, len do
    local encoded_stored = assert(logger:lpop(logname))
    local stored = cjson.decode(encoded_stored)
    entries[i] = stored.entry
    entries[i].log_req_headers = stored.log_req_headers
    assert(logger:rpush(logname, encoded_stored))
  end

  local count, err = logger:get(logname .. "|count")
  if err then
    error(err)
  end

  ngx.status = 200
  ngx.say(cjson.encode({
    entries = entries,
    count = count,
  }))
end


local function count_log(logname)
  local logger = get_logger()
  local count = assert(logger:get(logname .. "|count"))

  ngx.status = 200
  ngx.say(count)
end


local function reset_log(logname)
  local logger = get_logger()
  logger:delete(logname)
  logger:delete(logname .. "|count")
end


local function handle_ocsp()
  if ocsp_status == "good" then
    ngx.print(ngx.decode_base64(OCSP_RESPONSE_GOOD:gsub("\n", "")))

  elseif ocsp_status == "revoked" then
    ngx.print(ngx.decode_base64(OCSP_RESPONSE_REVOKED:gsub("\n", "")))

  elseif ocsp_status == "error" then
    ngx.exit(500)

  else
    assert("unknown ocsp_status:" ..ocsp_status)
  end
end


local function set_ocsp(status)
  ocsp_status = status
end


return {
  get_default_json_response   = get_default_json_response,
  filter_access_by_method     = filter_access_by_method,
  filter_access_by_basic_auth = filter_access_by_basic_auth,
  send_text_response          = send_text_response,
  send_default_json_response  = send_default_json_response,
  serve_web_sockets           = serve_web_sockets,
  store_log                   = store_log,
  retrieve_log                = retrieve_log,
  count_log                   = count_log,
  reset_log                   = reset_log,
  handle_ocsp                 = handle_ocsp,
  set_ocsp                    = set_ocsp,
}
