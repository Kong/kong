local ltn12 = require "ltn12"
local http = require "socket.http"
local url = require "socket.url"
local cjson = require "cjson"

local _M = {}

-- Builds a querystring from a table, separated by `&`
-- @param tab The key/value parameters
-- @param key The parent key if the value is multi-dimensional (optional)
-- @return a string representing the built querystring
local function build_query(tab, key)
  if ngx then
    return ngx.encode_args(tab)
  else
    local query = {}
    local keys = {}

    for k in pairs(tab) do
      keys[#keys+1] = k
    end

    table.sort(keys)

    for _,name in ipairs(keys) do
      local value = tab[name]
      if key then
        name = string.format("%s[%s]", tostring(key), tostring(name))
      end
      if type(value) == "table" then
        query[#query+1] = build_query(value, name)
      else
        value = tostring(value)
        if value ~= "" then
          query[#query+1] = string.format("%s=%s", name, value)
        else
          query[#query+1] = name
        end
      end
    end

    return table.concat(query, "&")
  end
end

local function http_call(options)
  -- Set Host header accordingly
  if not options.headers["host"] then
    local parsed_url = url.parse(options.url)
    local port_segment = ""
    if parsed_url.port then
      port_segment = ":"..parsed_url.port
    end
    options.headers["host"] = parsed_url.host..port_segment
  end

  -- Returns: response, code, headers
  local resp = {}
  options.sink = ltn12.sink.table(resp)

  local _, code, headers = http.request(options)
  return resp[1], code, headers
end

-- GET methpd
function _M.get(url, querystring, headers)
  if not headers then headers = {} end

  if querystring then
    url = string.format("%s?%s", url, build_query(querystring))
  end

  return http_call {
    method = "GET",
    url = url,
    headers = headers
  }
end

-- POST methpd
function _M.post(url, form, headers)
  if not headers then headers = {} end
  if not form then form = {} end

  local body = build_query(form)
  headers["content-length"] = string.len(body)
  if not headers["content-type"] then
    headers["content-type"] = "application/x-www-form-urlencoded"
  end

  return http_call {
    method = "POST",
    url = url,
    headers = headers,
    source = ltn12.source.string(body)
  }
end

-- POST MULTIPART methpd
function _M.post_multipart(url, form, headers)
  if not headers then headers = {} end
  if not form then form = {} end

  local boundary = "8fd84e9444e3946c"
  local body = ""
  for k,v in pairs(form) do
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

-- PUT method
function _M.put(url, table, headers)
  if not headers then headers = {} end
  if not table then table = {} end
  local raw_json = cjson.encode(table)

  headers["content-length"] = string.len(raw_json)
  if not headers["content-type"] then
    headers["content-type"] = "application/json"
  end

  return http_call {
    method = "PUT",
    url = url,
    headers = headers,
    source = ltn12.source.string(raw_json)
  }
end

-- DELETE method
function _M.delete(url, querystring, headers)
  if not headers then headers = {} end

  if querystring then
    url = string.format("%s?%s", url, build_query(querystring))
  end

  return http_call {
    method = "DELETE",
    url = url,
    headers = headers
  }
end

-- OPTIONS method
function _M.options(url, querystring, headers)
  if not headers then headers = {} end

  if querystring then
    url = string.format("%s?%s", url, build_query(querystring))
  end

  return http_call {
    method = "OPTIONS",
    url = url,
    headers = headers
  }
end

return _M