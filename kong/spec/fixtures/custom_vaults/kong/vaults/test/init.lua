local cjson = require "cjson"
local http = require "resty.http"

local fmt = string.format


local DEFAULTS_CONSUMED


---
-- Fake vault for integration tests.
local test = {
  VERSION = "1.0.0",
  SHM_NAME = "test_vault",
  PORT = 9876,
}


local function key_for(secret, version)
  assert(secret ~= nil, "missing secret")
  version = version or 1

  return fmt("secrets:%s:%s", secret, version)
end


local function get_from_shm(secret, version)
  local key = key_for(secret, version)
  local shm = assert(ngx.shared[test.SHM_NAME])

  local raw, err = shm:get(key)
  assert(err == nil, err)

  if raw then
    return cjson.decode(raw)
  end
end


local function delete_from_shm(secret)
  local key = key_for(secret)
  local shm = assert(ngx.shared[test.SHM_NAME])

  shm:delete(key)
end


function test.init()
end


function test.pause()
  local shm = ngx.shared[test.SHM_NAME]
  shm:set("paused", true)
  return kong.response.exit(200, { message = "succeed" })
end


function test.is_running()
  local shm = ngx.shared[test.SHM_NAME]
  return shm:get("paused") ~= true
end


function test.get(conf, resource, version)
  if not test.is_running() then
    return nil, "Vault server paused"
  end

  local secret = get_from_shm(resource, version)

  kong.log.inspect({
    conf     = conf,
    resource = resource,
    version  = version,
    secret   = secret,
  })

  secret = secret or {}

  local latency = conf.latency or secret.latency
  if latency then
    ngx.sleep(latency)
  end

  local raise_error = conf.raise_error or secret.raise_error
  local return_error = conf.return_error or secret.return_error

  if raise_error then
    error(raise_error)

  elseif return_error then
    return nil, return_error
  end

  local value = secret.value
  local ttl = secret.ttl

  if value == nil and not DEFAULTS_CONSUMED then
    -- default values to be used only once, during startup.  This is a hacky measure to make the test vault, which
    -- uses Kong's nginx, work.
    DEFAULTS_CONSUMED = true
    value = conf.default_value
    ttl = conf.default_value_ttl
  end

  return value, nil, ttl
end


function test.api()
  if not test.is_running() then
    return kong.response.exit(503, { message = "Vault server paused" })
  end

  local shm       = assert(ngx.shared[test.SHM_NAME])
  local secret    = assert(ngx.var.secret)
  local args      = assert(kong.request.get_query())
  local version   = tonumber(args.version) or 1

  local method = ngx.req.get_method()
  if method == "GET" then
    local value = get_from_shm(secret, version)
    if value ~= nil then
      return kong.response.exit(200, value)

    else
      return kong.response.exit(404, { message = "not found" })
    end

  elseif method == "DELETE" then
    delete_from_shm(secret)
    return kong.response.exit(204)

  elseif method ~= "PUT" then
    return kong.response.exit(405, { message = "method not allowed" })
  end


  local ttl = tonumber(args.ttl) or nil
  local raise_error = args.raise_error or nil
  local return_error = args.return_error or nil

  local value
  if not args.return_nil then
    value = kong.request.get_raw_body()

    if not value then
      return kong.response.exit(400, {
        message = "secret value expected, but the request body was empty"
      })
    end
  end

  local key = key_for(secret, version)
  local object = {
    value        = value,
    ttl          = ttl,
    raise_error  = raise_error,
    return_error = return_error,
  }

  assert(shm:set(key, cjson.encode(object)))

  return kong.response.exit(201, object)
end


test.client = {}


function test.client.put(secret, value, opts)
  local client = assert(http.new())

  opts = opts or {}

  if value == nil then
    opts.return_nil = true
  end

  local uri = fmt("http://127.0.0.1:%d/secret/%s", test.PORT, secret)

  local res, err = client:request_uri(uri, {
    method = "PUT",
    body = value,
    query = opts,
  })

  assert(err == nil, "failed PUT " .. uri .. ": " .. tostring(err))
  assert(res.status == 201, "failed PUT " .. uri .. ": " .. res.status)

  return cjson.decode(res.body)
end


function test.client.delete(secret)
  local client = assert(http.new())

  local uri = fmt("http://127.0.0.1:%d/secret/%s", test.PORT, secret)

  local res, err = client:request_uri(uri, {
    method = "DELETE",
  })

  assert(err == nil, "failed DELETE " .. uri .. ": " .. tostring(err))
  assert(res.status == 204, "failed DELETE " .. uri .. ": " .. res.status)
end


function test.client.get(secret, version)
  local query = version and { version = version } or nil

  local client = assert(http.new())

  local uri = fmt("http://127.0.0.1:%d/secret/%s", test.PORT, secret)

  local res, err = client:request_uri(uri, { query = query, method = "GET" })
  assert(err == nil, "failed GET " .. uri .. ": " .. tostring(err))

  return cjson.decode(res.body)
end


function test.client.pause()
  local client = assert(http.new())

  local uri = fmt("http://127.0.0.1:%d/pause", test.PORT)

  local res, err = client:request_uri(uri, { method = "GET" })
  assert(err == nil, "failed GET " .. uri .. ": " .. tostring(err))

  return cjson.decode(res.body)
end


test.http_mock = [[
  lua_shared_dict ]] .. test.SHM_NAME .. [[ 5m;

  server {
    server_name  "test-vault";
    listen 127.0.0.1:]] .. test.PORT .. [[;

    location ~^/secret/(?<secret>.+) {
      content_by_lua_block {
        require("kong.vaults.test").api()
      }
    }

    location ~^/pause {
      content_by_lua_block {
        require("kong.vaults.test").pause()
      }
    }
  }
]]


return test
