local ssl_fixtures = require "spec.03-plugins.ssl.fixtures"
local helpers = require "spec.helpers"
local cache = require "kong.tools.database_cache"
local pl_stringx = require "pl.stringx"
local pl_utils = require "pl.utils"
local pl_file = require "pl.file"
local pl_path = require "pl.path"
local url = require "socket.url"

describe("Plugin hooks: ssl", function()
  local api, plugin, admin_client, proxy_client
  teardown(function()
    if admin_client and proxy_client then
      admin_client:close()
      proxy_client:close()
    end
    helpers.stop_kong()
  end)

  before_each(function()
    helpers.kill_all()
    assert(helpers.start_kong())

    api = assert(helpers.dao.apis:insert {
      request_host = "ssl1.com",
      upstream_url = "http://mockbin.com"
    })
    plugin = assert(helpers.dao.plugins:insert {
      name = "ssl",
      api_id = api.id,
      config = {
        cert = ssl_fixtures.cert,
        key = ssl_fixtures.key
      }
    })
    
    proxy_client = assert(helpers.http_client("127.0.0.1", pl_stringx.split(helpers.test_conf.proxy_listen_ssl, ":")[2]))
    proxy_client:ssl_handshake()
    admin_client = assert(helpers.http_client("127.0.0.1", helpers.test_conf.admin_port))
  end)

  describe("SSL plugin entity invalidation", function()
    it("invalidates when SSL plugin is deleted", function()
      -- It should work
      local parsed_url = url.parse("https://"..helpers.test_conf.proxy_listen_ssl)
      local _, _, stdout = pl_utils.executeex("(echo \"GET /\"; sleep 2) | openssl s_client -connect "..parsed_url.host..":"..tostring(parsed_url.port).." -servername ssl1.com")
      assert.is_string(stdout:match("US/ST=California/L=San Francisco/O=Kong/OU=IT/CN=ssl1.com"))
      
      -- Check that cache is populated
      local cache_key = cache.ssl_data(api.id)
      local res = assert(admin_client:send {
        method = "GET",
        path = "/cache/"..cache_key,
        headers = {}
      })
      assert.res_status(200, res)

      -- Delete SSL plugin (which triggers invalidation)
      local res = assert(admin_client:send {
        method = "DELETE",
        path = "/apis/ssl1.com/plugins/"..plugin.id,
        headers = {}
      })
      assert.res_status(204, res)

      -- ensure cache is invalidated
      helpers.wait_until(function()
        local res = assert(admin_client:send {
          method = "GET",
          path = "/cache/"..cache_key
        })
        res:read_body()
        return res.status == 404
      end)

      -- It should not work
      local _, _, stdout = pl_utils.executeex("(echo \"GET /\"; sleep 2) | openssl s_client -connect "..parsed_url.host..":"..tostring(parsed_url.port).." -servername ssl1.com")
      assert.is_nil(stdout:match("US/ST=California/L=San Francisco/O=Kong/OU=IT/CN=ssl1.com"))
    end)
    it("invalidates when SSL plugin entity is updated", function()
      -- It should work
      local parsed_url = url.parse("https://"..helpers.test_conf.proxy_listen_ssl)
      local _, _, stdout = pl_utils.executeex("(echo \"GET /\"; sleep 2) | openssl s_client -connect "..parsed_url.host..":"..tostring(parsed_url.port).." -servername ssl1.com")
      assert.is_string(stdout:match("US/ST=California/L=San Francisco/O=Kong/OU=IT/CN=ssl1.com"))

      -- Check that cache is populated
      local cache_key = cache.ssl_data(api.id)
      local res = assert(admin_client:send {
        method = "GET",
        path = "/cache/"..cache_key,
        headers = {}
      })
      assert.res_status(200, res)

      -- Update SSL plugin (which triggers invalidation)
      local res = assert(admin_client:send {
        method = "PATCH",
        path = "/apis/ssl1.com/plugins/"..plugin.id,
        body = {
          ["config.cert"] = assert(pl_file.read(pl_path.join(helpers.test_conf.prefix, "ssl", "kong-default.crt"))),
          ["config.key"] = assert(pl_file.read(pl_path.join(helpers.test_conf.prefix, "ssl", "kong-default.key")))
        },
        headers = {
          ["Content-Type"] = "multipart/form-data"
        }
      })
      assert.res_status(200, res)

      -- ensure cache is invalidated
      helpers.wait_until(function()
        local res = assert(admin_client:send {
          method = "GET",
          path = "/cache/"..cache_key
        })
        res:read_body()
        return res.status == 404
      end)

      -- It should not work
      local _, _, stdout = pl_utils.executeex("(echo \"GET /\"; sleep 2) | openssl s_client -connect "..parsed_url.host..":"..tostring(parsed_url.port).." -servername ssl1.com")
      assert.is_nil(stdout:match("US/ST=California/L=San Francisco/O=Kong/OU=IT/CN=ssl1.com"))
      assert.is_string(stdout:match("US/ST=California/L=San Francisco/O=Kong/OU=IT Department/CN=localhost"))
    end)
  end)

  describe("API entity invalidation", function()
    it("should invalidate when API entity is deleted", function()
      -- It should work
      local parsed_url = url.parse("https://"..helpers.test_conf.proxy_listen_ssl)
      local _, _, stdout = pl_utils.executeex("(echo \"GET /\"; sleep 2) | openssl s_client -connect "..parsed_url.host..":"..tostring(parsed_url.port).." -servername ssl1.com")
      assert.is_string(stdout:match("US/ST=California/L=San Francisco/O=Kong/OU=IT/CN=ssl1.com"))

      -- Check that cache is populated
      local cache_key = cache.ssl_data(api.id)
      local res = assert(admin_client:send {
        method = "GET",
        path = "/cache/"..cache_key,
        headers = {}
      })
      assert.res_status(200, res)

      -- delete API entity
      res = assert(admin_client:send {
        method = "DELETE",
        path = "/apis/ssl1.com"
      })
      assert.res_status(204, res)

      -- ensure cache is invalidated
      helpers.wait_until(function()
        local res = assert(admin_client:send {
          method = "GET",
          path = "/cache/"..cache_key
        })
        res:read_body()
        return res.status == 404
      end)

      -- It should not work
      local _, _, stdout = pl_utils.executeex("(echo \"GET /\"; sleep 2) | openssl s_client -connect "..parsed_url.host..":"..tostring(parsed_url.port).." -servername ssl1.com")
      assert.is_nil(stdout:match("US/ST=California/L=San Francisco/O=Kong/OU=IT/CN=ssl1.com"))
    end)
  end)
end)
