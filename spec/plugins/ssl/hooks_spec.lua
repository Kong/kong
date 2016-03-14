local json = require "cjson"
local http_client = require "kong.tools.http_client"
local spec_helper = require "spec.spec_helpers"
local cache = require "kong.tools.database_cache"
local ssl_fixtures = require "spec.plugins.ssl.fixtures"
local IO = require "kong.tools.io"
local url = require "socket.url"

local STUB_GET_SSL_URL = spec_helper.STUB_GET_SSL_URL
local API_URL = spec_helper.API_URL

describe("SSL Hooks", function()

  setup(function()
    spec_helper.prepare_db()
  end)

  teardown(function()
    spec_helper.stop_kong()
  end)

  before_each(function()
    spec_helper.restart_kong()

    spec_helper.drop_db()
    spec_helper.insert_fixtures {
      api = {
        { request_host = "ssl1.com", upstream_url = "http://mockbin.com" }
      }
    }

    -- The SSL plugin needs to be added manually because we are requiring ngx.ssl
    local _, status = http_client.post_multipart(API_URL.."/apis/ssl1.com/plugins/", { 
      name = "ssl", 
      ["config.cert"] = ssl_fixtures.cert, 
      ["config.key"] = ssl_fixtures.key})
    assert.equals(201, status)
  end)

  describe("SSL plugin entity invalidation", function()
    it("should invalidate when SSL plugin is deleted", function()
      -- It should work
      local parsed_url = url.parse(STUB_GET_SSL_URL)
      local res = IO.os_execute("(echo \"GET /\"; sleep 2) | openssl s_client -connect "..parsed_url.host..":"..tostring(parsed_url.port).." -servername ssl1.com")

      assert.truthy(res:match("US/ST=California/L=San Francisco/O=Kong/OU=IT/CN=ssl1.com"))
      
      -- Check that cache is populated
      local response, status = http_client.get(API_URL.."/apis/", {request_host="ssl1.com"})
      assert.equals(200, status)
      local api_id = json.decode(response).data[1].id
      assert.truthy(api_id)

      local cache_key = cache.ssl_data(api_id)
      local _, status = http_client.get(API_URL.."/cache/"..cache_key)
      assert.equals(200, status)

      -- Retrieve SSL plugin
      local response, status = http_client.get(API_URL.."/plugins/", {api_id=api_id, name="ssl"})
      assert.equals(200, status)
      local plugin_id = json.decode(response).data[1].id
      assert.truthy(plugin_id)

      -- Delete SSL plugin (which triggers invalidation)
      local _, status = http_client.delete(API_URL.."/plugins/"..plugin_id)
      assert.equals(204, status)

      -- Wait for cache to be invalidated
      local exists = true
      while(exists) do
        local _, status = http_client.get(API_URL.."/cache/"..cache_key)
        if status ~= 200 then
          exists = false
        end
      end

      -- It should not work
      local parsed_url = url.parse(STUB_GET_SSL_URL)
      local res = IO.os_execute("(echo \"GET /\"; sleep 2) | openssl s_client -connect "..parsed_url.host..":"..tostring(parsed_url.port).." -servername ssl1.com")

      assert.falsy(res:match("US/ST=California/L=San Francisco/O=Kong/OU=IT/CN=ssl1.com"))
    end)
    it("should invalidate when Basic Auth Credential entity is updated", function()
      -- It should work
      local parsed_url = url.parse(STUB_GET_SSL_URL)
      local res = IO.os_execute("(echo \"GET /\"; sleep 2) | openssl s_client -connect "..parsed_url.host..":"..tostring(parsed_url.port).." -servername ssl1.com")

      assert.truthy(res:match("US/ST=California/L=San Francisco/O=Kong/OU=IT/CN=ssl1.com"))

      -- Check that cache is populated
      local response, status = http_client.get(API_URL.."/apis/", {request_host="ssl1.com"})
      assert.equals(200, status)
      local api_id = json.decode(response).data[1].id
      assert.truthy(api_id)

      local cache_key = cache.ssl_data(api_id)
      local _, status = http_client.get(API_URL.."/cache/"..cache_key)
      assert.equals(200, status)

      -- Retrieve SSL plugin
      local response, status = http_client.get(API_URL.."/plugins/", {api_id=api_id, name="ssl"})
      assert.equals(200, status)
      local plugin_id = json.decode(response).data[1].id
      assert.truthy(plugin_id)
      
      -- Update SSL plugin (which triggers invalidation)
      local kong_working_dir = spec_helper.get_env(spec_helper.TEST_CONF_FILE).configuration.nginx_working_dir
      local ssl_cert_path = IO.path:join(kong_working_dir, "ssl", "kong-default.crt")
      local ssl_key_path = IO.path:join(kong_working_dir, "ssl", "kong-default.key")

      local res = IO.os_execute("curl -X PATCH -s -o /dev/null -w \"%{http_code}\" "..API_URL.."/apis/"..api_id.."/plugins/"..plugin_id.." --form \"config.cert=@"..ssl_cert_path.."\" --form \"config.key=@"..ssl_key_path.."\"")
      assert.are.equal(200, tonumber(res))

      -- Wait for cache to be invalidated
      local exists = true
      while(exists) do
        local _, status = http_client.get(API_URL.."/cache/"..cache_key)
        if status ~= 200 then
          exists = false
        end
      end

      -- It should not work
      local parsed_url = url.parse(STUB_GET_SSL_URL)
      local res = IO.os_execute("(echo \"GET /\"; sleep 2) | openssl s_client -connect "..parsed_url.host..":"..tostring(parsed_url.port).." -servername ssl1.com")

      assert.falsy(res:match("US/ST=California/L=San Francisco/O=Kong/OU=IT/CN=ssl1.com"))
      assert.truthy(res:match("US/ST=California/L=San Francisco/O=Kong/OU=IT Department/CN=localhost"))
    end)
  end)

  describe("API entity invalidation", function()
    it("should invalidate when API entity is deleted", function()
      -- It should work
      local parsed_url = url.parse(STUB_GET_SSL_URL)
      local res = IO.os_execute("(echo \"GET /\"; sleep 2) | openssl s_client -connect "..parsed_url.host..":"..tostring(parsed_url.port).." -servername ssl1.com")

      assert.truthy(res:match("US/ST=California/L=San Francisco/O=Kong/OU=IT/CN=ssl1.com"))

       -- Check that cache is populated
      local response, status = http_client.get(API_URL.."/apis/", {request_host="ssl1.com"})
      assert.equals(200, status)
      local api_id = json.decode(response).data[1].id
      assert.truthy(api_id)

      local cache_key = cache.ssl_data(api_id)
      local _, status = http_client.get(API_URL.."/cache/"..cache_key)
      assert.equals(200, status)
      
      -- Delete API (which triggers invalidation)
      local _, status = http_client.delete(API_URL.."/apis/"..api_id)
      assert.equals(204, status)

      -- Wait for cache to be invalidated
      local exists = true
      while(exists) do
        local _, status = http_client.get(API_URL.."/cache/"..cache_key)
        if status ~= 200 then
          exists = false
        end
      end

      -- It should not work
      local parsed_url = url.parse(STUB_GET_SSL_URL)
      local res = IO.os_execute("(echo \"GET /\"; sleep 2) | openssl s_client -connect "..parsed_url.host..":"..tostring(parsed_url.port).." -servername ssl1.com")

      assert.falsy(res:match("US/ST=California/L=San Francisco/O=Kong/OU=IT/CN=ssl1.com"))
    end) 
  end)
end)
