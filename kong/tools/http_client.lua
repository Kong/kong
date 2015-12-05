local https = require "ssl.https"
local url = require "socket.url"
local http = require "socket.http"
local json = require "cjson"
local ltn12 = require "ltn12"

local _M = {}

local function get_response(resp)
  if #resp == 0 then
    return nil
  else
    return table.concat(resp, "")
  end
end

local function http_call(options)
  -- Set Host header accordingly
  local parsed_url = url.parse(options.url)

  if not options.headers["host"] then
    local port_segment = ""
    if parsed_url.port then
      port_segment = ":"..parsed_url.port
    end
    options.headers["host"] = parsed_url.host..port_segment
  end

  -- Returns: response, code, headers
  local resp = {}
  options.sink = ltn12.sink.table(resp)

  if parsed_url.scheme == "https" then
    options.protocol = "tlsv1"
    options.mode = "client"
    options.options = "all"

    local _, code, headers = https.request(options)
    return get_response(resp), code, headers
  else
    local _, code, headers = http.request(options)
    return get_response(resp), code, headers
  end
end

local function with_body(method)
  return function(url, body, headers)
    if not headers then headers = {} end
    if not body then body = {} end

    if headers["content-type"] == "application/json" then
      if type(body) == "table" then
        body = json.encode(body)
      end
    else
      headers["content-type"] = "application/x-www-form-urlencoded"
      if type(body) == "table" then
        body = ngx.encode_args(body, true)
      end
    end

    headers["content-length"] = string.len(body)

    return http_call {
      method = method:upper(),
      url = url,
      headers = headers,
      source = ltn12.source.string(body)
    }
  end
end

local function without_body(method)
  return function(url, querystring, headers)
    if not headers then headers = {} end

    if querystring then
      url = string.format("%s?%s", url, ngx.encode_args(querystring, true))
    end

    return http_call {
      method = method:upper(),
      url = url,
      headers = headers
    }
  end
end

_M.put = with_body("PUT")
_M.post = with_body("POST")
_M.patch = with_body("PATCH")
_M.get = without_body("GET")
_M.delete = without_body("DELETE")
_M.options = without_body("OPTIONS")

function _M.post_multipart(url, form, headers)
  if not headers then headers = {} end
  if not form then form = {} end

  local boundary = "8fd84e9444e3946c"
  local body = ""
  for k, v in pairs(form) do
    body = body.."--"..boundary.."\r\nContent-Disposition: form-data; name=\""..k.."\"\r\n\r\n"..v.."\r\n"
  end

  if body ~= "" then
    body = body.."--"..boundary.."--\r\n"
  end

  headers["content-length"] = string.len(body)
  if not headers["content-type"] then
    headers["content-type"] = "multipart/form-data; boundary="..boundary
  end

  return http_call {
    method = "POST",
    url = url,
    headers = headers,
    source = ltn12.source.string(body)
  }
end

return _M
