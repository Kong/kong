local ssl_fixtures = require "spec.03-plugins.16-ssl.fixtures"
local helpers = require "spec.helpers"
local cache = require "kong.tools.database_cache"

local function get_cert()
  local _, _, stdout = assert(helpers.execute(
    "echo 'GET /' | openssl s_client -connect "..
    "0.0.0.0:"..helpers.test_conf.proxy_ssl_port.." -servername ssl1.com"))
  return stdout
end

describe("Plugin hooks: ssl", function()
  local api, plugin, admin_client

  before_each(function()
    helpers.dao:truncate_tables()
    assert(helpers.start_kong())
    admin_client = helpers.admin_client()

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
  end)
  after_each(function()
    if admin_client then
      admin_client:close()
    end
    helpers.kill_all()
  end)

  describe("SSL plugin invalidations", function()
    it("on deletion", function()
      assert.matches("US/ST=California/L=San Francisco/O=Kong/OU=IT/CN=ssl1.com", get_cert(), nil, true)

      -- Check that cache is populated
      local cache_key = cache.ssl_data(api.id)
      local res = assert(admin_client:send {
        method = "GET",
        path = "/cache/"..cache_key
      })
      assert.res_status(200, res)

      -- Delete SSL plugin (which triggers invalidation)
      local res = assert(admin_client:send {
        method = "DELETE",
        path = "/apis/ssl1.com/plugins/"..plugin.id
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

      assert.not_matches("US/ST=California/L=San Francisco/O=Kong/OU=IT/CN=ssl1.com", get_cert(), nil, true)
    end)
    it("on update", function()
      assert.matches("US/ST=California/L=San Francisco/O=Kong/OU=IT/CN=ssl1.com", get_cert(), nil, true)

      -- check that cache is populated
      local cache_key = cache.ssl_data(api.id)
      local res = assert(admin_client:send {
        method = "GET",
        path = "/cache/"..cache_key,
        headers = {}
      })
      assert.res_status(200, res)

      -- update SSL plugin (which triggers invalidation)
      local res = assert(admin_client:send {
        method = "PATCH",
        path = "/apis/ssl1.com/plugins/"..plugin.id,
        body = {
          ["config.cert"] = helpers.file.read(helpers.test_conf.ssl_cert),
          ["config.key"] = helpers.file.read(helpers.test_conf.ssl_cert_key)
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

      assert.not_matches("US/ST=California/L=San Francisco/O=Kong/OU=IT/CN=ssl1.com", get_cert(), nil, true)
    end)
  end)

  describe("API invalidations", function()
    it("on deletion", function()
      assert.matches("US/ST=California/L=San Francisco/O=Kong/OU=IT/CN=ssl1.com", get_cert(), nil, true)

      -- check that cache is populated
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

      assert.not_matches("US/ST=California/L=San Francisco/O=Kong/OU=IT/CN=ssl1.com", get_cert(), nil, true)
    end)
  end)
end)
