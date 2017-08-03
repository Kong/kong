local utils      = require "kong.tools.utils"
local cjson_safe = require "cjson.safe"

local function filter_access_by_method(method)
  if ngx.req.get_method() ~= method then
    ngx.status = ngx.HTTP_NOT_ALLOWED
    ngx.header["X-Powered-By"] = "mock_upstream"
    ngx.say("The method is not allowed for the requested URL")
    return ngx.exit(ngx.HTTP_NOT_ALLOWED)
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


local function send_text_response(text, content_type)
  content_type               = content_type or "text/plain"
  ngx.header["X-Powered-By"] = "mock_upstream"

  text = ngx.req.get_method() == "HEAD" and "" or tostring(text)

  ngx.header["Content-Length"] = #text + 1
  ngx.header["Content-Type"]   = content_type
  return ngx.say(text)
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

  return nil, "could not read body data or body file"
end


local function get_default_json_response()
  local req                = ngx.req
  local headers            = req.get_headers(0)
  local data, form, params = "", {}, cjson_safe.null
  local ct                 = headers["content-type"]
  if ct then
    req.read_body()
    if string.find(ct, "application/x-www-form-urlencoded", nil, true) then
      form = req.get_post_args()

    elseif string.find(ct, "application/json", nil, true) then
      local err
      data, err = get_body_data()
      if not data then
        ngx.log(ngx.ERR, "could not read body data: ", err)
        return ngx.exit(ngx.HTTP_INTERNAL_SERVER_ERROR)
      end
      -- ignore decoding errors
      params = cjson_safe.decode(data) or cjson_safe.null
    end
  end

  return {
    args    = ngx.req.get_uri_args(),
    data    = data,
    form    = form,
    headers = headers,
    params  = params,
    url     = string.format("%s://%s%s", ngx.var.scheme,
                            ngx.var.host, ngx.var.request_uri),
    vars    = get_ngx_vars(),
  }
end


local function send_default_json_response(extra)
  local cjson = require "cjson"
  local tbl   = utils.table_merge(get_default_json_response(), extra)
  return send_text_response(cjson.encode(tbl), "application/json")
end


local function serve_web_sockets()
  local server = require "resty.websocket.server"
  local wb, err = server:new{
    timeout = 5000,
    max_payload_len = 65535,
  }

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


return {
  filter_access_by_method     = filter_access_by_method,
  filter_access_by_basic_auth = filter_access_by_basic_auth,
  send_text_response          = send_text_response,
  send_default_json_response  = send_default_json_response,
  serve_web_sockets           = serve_web_sockets,
}
