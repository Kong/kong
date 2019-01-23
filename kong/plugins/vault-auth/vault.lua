local http = require "resty.http"
local cjson = require "cjson.safe"


local _M = {}


_M.version = "0.1"


local expected_status = {
  LIST   = 200,
  GET    = 200,
  POST   = 204,
  DELETE = 204,
}


function _M:query(method, key, body, raw)
  local c = http.new()

  local opts = {
    method  = method,
    headers = {
      ["X-Vault-Token"] = self.vault_token
    },
  }
  if body then
    opts.headers["Content-Type"] = "application/json"
    opts.body = cjson.encode(body)
  end

  local path = self:build_kv_v1_base_path()
  if method ~= "LIST" then
    path = path .. "/" .. key
  end

  local res, err = c:request_uri(path, opts)
  if err then
    return nil, "transport error: " .. err
  end

  if res.status == 404 then
    return nil, "not found"
  end

  if res.status ~= expected_status[method] then
    return nil, "unexpected response: " .. res.body
  end

  if res.status == 204 then
    return true
  end

  if raw then
    return res.body
  end

  local data, err = cjson.decode(res.body)
  if err then
    return nil, "error decoding response body: ", err
  end

  return data.data
end


function _M:build_kv_v1_base_path()
  return self.protocol        ..
         "://"                ..
         self.host            ..
         ":"                  ..
         tostring(self.port)  ..
         "/v1/"               ..
         self.mount
end


function _M:fetch(key)
  return self:query("GET", key)
end


function _M:fetch_raw(key)
  return self:query("GET", key, nil, true)
end


function _M:list()
  return self:query("LIST")
end


function _M:list_raw()
  return self:query("LIST", nil, nil, true)
end


function _M:post(key, data)
  return self:query("POST", key, data)
end


function _M:post_raw(key, data)
  return self:query("POST", key, data, true)
end


function _M:delete(key)
  return self:query("DELETE", key)
end


function _M:delete_raw(key)
  return self:query("DELETE", key, nil, true)
end


function _M.new(opts)
  return setmetatable(opts, {
    __index = _M,
  })
end


return _M
