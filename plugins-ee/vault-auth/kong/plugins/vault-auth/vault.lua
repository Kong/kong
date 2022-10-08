-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local http = require "resty.http"
local cjson = require "cjson.safe"


local _M = {}


_M.version = "0.1"


local expected_status = {
  LIST   = { [200] = true },
  GET    = { [200] = true },
  POST   = { [204] = true, [200] = true },
  DELETE = { [204] = true, [200] = true }
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
    opts.body = self:prepare_body(body)
  end
  local path = self:build_base_path(method)
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

  if not expected_status[method][res.status] then
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

  return self:unwrap_data(data.data, method)
end


function _M:unwrap_data(data, method)
  if self.kv == "v2" and method == "GET" then
    return data.data
  end
  return data
end


function _M:prepare_body(body)
  local payload = body
  if self.kv == "v2" then
    payload = { data = body }
  end
  return cjson.encode(payload)
end


function _M:build_base_path(method)
  local path = self:build_kv_v1_base_path()

  if self.kv == "v2" then
    return path .. (method == "LIST" and "/metadata" or "/data")
  end
  return path
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


function _M.cache_key(access_token, vault_id)
  return "vault-auth:" .. access_token  .. ":" .. vault_id
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
