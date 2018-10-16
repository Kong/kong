local utils      = require "kong.tools.utils"
local cjson_safe = require "cjson.safe"
local cjson      = require "cjson"
local ws_server  = require "resty.websocket.server"
local pl_stringx = require "pl.stringx"


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
  local tbl = utils.table_merge(get_default_json_response(), extra_fields)
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


local function store_log(logname)
  ngx.req.read_body()
  local body = ngx.req.get_body_data()
  local loggers = ngx.shared["kong_mock_upstream_loggers"]
  if not loggers then
    loggers = {}
    ngx.shared["kong_mock_upstream_loggers"] = loggers
  end
  loggers[logname] = loggers[logname] or {}
  local headers = {}
  for k, v in pairs(ngx.req.get_headers()) do
    table.insert(headers, { name = k:lower(), value = v })
  end
  table.insert(loggers[logname], {
    request = {
      headers = headers,
      postData = {
        text = body,
      }
    }
  })
  ngx.status = 200
  return send_default_json_response({
    code = 200,
  })
end


local function retrieve_log(logname)
  local loggers = ngx.shared["kong_mock_upstream_loggers"]
  if not loggers then
    loggers = {}
    ngx.shared["kong_mock_upstream_loggers"] = loggers
  end
  loggers[logname] = loggers[logname] or {}
  ngx.status = 200
  ngx.say(cjson.encode({
    log = {
      entries = loggers[logname],
    }
  }))
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
}
