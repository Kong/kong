local http = require "socket.http"
local url = require "socket.url"
local cjson = require "cjson"

-- Builds a querystring from a table, separated by `&`
-- @param tab The key/value parameters
-- @param key The parent key if the value is multi-dimensional (optional)
-- @return a string representing the built querystring
function build_query(tab, key)
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
      local value = tostring(value)
      if value ~= "" then
        query[#query+1] = string.format("%s=%s", name, value)
      else
        query[#query+1] = name
      end
    end
  end

  return table.concat(query, "&")
end


local _M = {}

function _M.http_call(method, url, querystring, body, cb)
  local bodyStr

  if querystring then
    url = string.format("%s?%s", url, build_query(querystring))
  end

  if body then
    bodyStr = build_query(body)
  end

  local body, res_code, res_headers, res_status = http.request(url, bodyStr)

  --print('body: ' .. body)
  --print('code: ' .. tostring(res_code))
  --print('headers: ' .. inspect(res_headers))

  if cb then
    cb(res_code, cjson.decode(body), res_headers)
  end
end

function _M.get(url, querystring, cb)
  _M.http_call("GET", url, querystring, nil, cb)
end

function _M.post(url, form, cb)
  _M.http_call("POST", url, nil, form, cb)
end

return _M