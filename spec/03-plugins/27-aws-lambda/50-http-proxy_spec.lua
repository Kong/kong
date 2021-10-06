require "spec.helpers"
local http = require "resty.http"

local configs = {
  {
    name = "plain #http",
    scheme = "http",
    host = "httpbin.org",
    path = "/anything",
  },{
    name = "plain #https",
    scheme = "https",
    host = "httpbin.org",
    path = "/anything",
  },{
    name = "#http via proxy",
    scheme = "http",
    host = "mockbin.org",
    path = "/request",
    proxy_url = "http://127.0.0.1:3128/",
  },{
    name = "#https via proxy",
    scheme = "https",
    host = "mockbin.org",
    path = "/request",
    proxy_url = "http://127.0.0.1:3128/",
  },{
    name = "#http via authenticated proxy",
    scheme = "http",
    host = "httpbin.org",
    path = "/anything",
    proxy_url = "http://127.0.0.1:3128/",
    authorization = "Basic a29uZzpraW5n",  -- base64("kong:king")
  },{
    name = "#https via authenticated proxy",
    scheme = "https",
    host = "httpbin.org",
    path = "/anything",
    proxy_url = "http://127.0.0.1:3128/",
    authorization = "Basic a29uZzpraW5n",  -- base64("kong:king")
  }
}

local max_idle_timeout = 3

local function make_request(config)
  -- create and connect the client
  local client = http.new()
  local ok, err = client:connect {
    scheme = config.scheme,
    host = config.host,
    port = config.scheme == "https" and 443 or 80,
    ssl_verify = config.scheme == "https" and false,
    ssl_server_name = config.scheme == "https" and config.host,
    proxy_opts = config.proxy_url and {
      http_proxy = config.proxy_url,
      http_proxy_authorization = config.authorization,
    }
  }
  assert.is_nil(err)
  assert.truthy(ok)

  -- make the request
  local res, err = client:request {
    method = "GET",
    path = config.path,
    body = nil,
    headers = {
      Host = config.host,
      -- for plain http; proxy-auth must be in the headers
      ["Proxy-Authorization"] = (config.scheme == "http" and config.authorization),
    }
  }

  assert.is_nil(err)
  assert.truthy(res)

  -- read the body to finish socket ops
  res.body = res:read_body()
  local reuse = client.sock:getreusedtimes()

  -- close it
  ok, err = client:set_keepalive(max_idle_timeout)  --luacheck: ignore
  --assert.is_nil(err)  -- result can be: 2, with error connection had to be closed
  assert.truthy(ok)     -- resul 2 also qualifies as truthy.

  -- verify http result
  if res.status ~= 200 then assert.equal({}, res) end
  assert.equal(200, res.status)
  return reuse
end




describe("#proxy #squid", function()
  lazy_teardown(function()
    ngx.sleep(max_idle_timeout + 0.5) -- wait for keepalive to expire and all socket pools to become empty again
  end)

  for _, config in ipairs(configs) do
    it("Make a request " .. config.name, function()
      make_request(config)
    end)
  end

end)



describe("#keepalive #squid", function()
  lazy_teardown(function()
    ngx.sleep(max_idle_timeout + 0.5) -- wait for keepalive to expire and all socket pools to become empty again
  end)

  for _, config in ipairs(configs) do
    it("Repeat a request " .. config.name, function()
      local reuse = 0
      local loop_size = 10

      for i = 1, loop_size do
        local conn_count = make_request(config)
        reuse = math.max(reuse, conn_count)
      end

      --print(reuse)
      assert(reuse > 0, "expected socket re-use to be > 0, but got: " .. tostring(reuse))
      assert(reuse < loop_size, "re-use expected to be less than " .. loop_size ..
              " but was " .. reuse .. ". So probably the socket-poolname is not unique?")
    end)
  end

end)
