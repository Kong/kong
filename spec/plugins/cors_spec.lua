local spec_helper = require "spec.spec_helpers"
local http_client = require "kong.tools.http_client"
local cjson = require "cjson"

local APIS = {}
local PLUGINS = {}
local API_URL = spec_helper.API_URL
local PROXY_URL = spec_helper.PROXY_URL

function request(name, method, qs, headers)
  headers = merge({ host = get_dns(name) }, headers or {})
  return http_client[method](PROXY_URL, qs, headers)
end

function create_api(name, dns)
  local response, status, headers = http_client.post(API_URL.."/apis/", { name=name, target_url="http://mockbin.com", public_dns=(dns or "mockbin.com") }, {})

  -- decode response
  response = cjson.decode(response)

  -- store id for later usage
  APIS[name] = { id = response.id, dns = dns }
end

function delete_api(name)
  local response, status, headers = http_client.delete(API_URL.."/apis/"..get_id(name))

  -- remove api if we obtain 200
  if status == 200 then
    APIS[name] = nil
  end

  -- ensure api has been deleted
  assert.are.equal(get_id(name), nil)
end

function delete_apis()
  for name, t in pairs(APIS) do
    local response, status, headers = http_client.delete(API_URL.."/apis/"..t.id)
    assert.are.equal(status, 204)
  end
  APIS = {}
end

function enable_plugin(api_name, name, options)
  local plugin = merge({ name=name, api_id=get_id(api_name) }, options or {})
  local response, status, headers = http_client.post(API_URL.."/plugins_configurations/", plugin)

  -- ensure created
  assert.are.equal(status, 201)

  -- decode response
  response = cjson.decode(response)

  -- store for later usage
  table.insert(PLUGINS, response.id)

  -- return results
  return response, status, headers
end

function delete_plugins()
  for i, id in ipairs(PLUGINS) do
    local response, status, headers = http_client.delete(API_URL.."/plugins_configurations/"..id)
    assert.are.equal(status, 204)
  end
  PLUGINS = {}
end

function get_id(name)
  return APIS[name].id
end

function get_dns(name)
  return APIS[name].dns
end

function merge (a, b)
  for k, v in pairs(b) do a[k] = v end
  return a
end

function print_table (t)
  for k, v in pairs(t) do print(k, v) end
end

describe("CORS Plugin", function()

  setup(function()
    spec_helper.prepare_db()
    spec_helper.start_kong()

    create_api("API_TESTS_1", "mockbin.com")
    create_api("API_TESTS_2", "mockbin2.com")
    create_api("API_TESTS_3", "mockbin3.com")
    create_api("API_TESTS_4", "mockbin4.com")
  end)

  teardown(function()
    spec_helper.stop_kong()
    spec_helper.reset_db()
  end)

  describe("Schema", function()
    after_each(function()
      delete_plugins()
    end)

    it("should set the appropriate defaults", function()
      local response, status, headers = enable_plugin("API_TESTS_1", "cors")

      -- assertions
      assert.are.equal(status, 201)
      assert.are.equal(response.value.preflight_continue, false)
      assert.are.equal(response.value.credentials, false)
      assert.are.equal(response.value.methods, nil)
      assert.are.equal(response.value.headers, nil)
      assert.are.equal(response.value.max_age, nil)
      assert.are.equal(response.value.origin, nil)
    end)

    it("should ignore values outside of the schema", function()
      local options = { values={ testing="invalid" } }
      local response, status, headers = enable_plugin("API_TESTS_1", "cors", options)

      -- assertions
      assert.are.equal(status, 201)
      assert.falsy(response.value.testing)
    end)
  end)

  describe("OPTIONS", function()
    after_each(function()
      delete_plugins()
    end)

    it("should give appropriate defaults when no options are passed", function()
      enable_plugin("API_TESTS_1", "cors")

      -- make proxy request
      local response, status, headers = request("API_TESTS_1", "options")

      -- assertions
      assert.are.equal(headers["access-control-allow-origin"], "*")
      assert.are.equal(headers["access-control-allow-methods"], "GET,HEAD,PUT,PATCH,POST,DELETE")
      assert.are.equal(headers["access-control-allow-headers"], nil)
      assert.are.equal(headers["access-control-expose-headers"], nil)
      assert.are.equal(headers["access-control-allow-credentials"], nil)
      assert.are.equal(headers["access-control-max-age"], nil)
    end)

    it("should reflect what is specified in options", function()
      local options = {}

      -- setup options
      options["value.origin"] = "example.com"
      options["value.methods"] = "GET"
      options["value.headers"] = "origin, type, accepts"
      options["value.exposed_headers"] = "x-auth-token"
      options["value.max_age"] = 23
      options["value.credentials"] = true

      -- enable plugin
      enable_plugin("API_TESTS_2", "cors", options)

      -- make proxy request
      local response, status, headers = request("API_TESTS_2", "options")

      -- assertions
      assert.are.equal(headers["access-control-allow-origin"], options["value.origin"])
      assert.are.equal(headers["access-control-allow-headers"], options["value.headers"])
      assert.are.equal(headers["access-control-expose-headers"], nil)
      assert.are.equal(headers["access-control-allow-methods"], options["value.methods"])
      assert.are.equal(headers["access-control-max-age"], tostring(options["value.max_age"]))
      assert.are.equal(headers["access-control-allow-credentials"], "true")
    end)
  end)

  describe("GET,PUT,POST,ETC", function()
    after_each(function()
      delete_plugins()
    end)

    it("should give appropriate defaults when no options are passed", function()
      enable_plugin("API_TESTS_3", "cors")

      -- make proxy request
      local response, status, headers = request("API_TESTS_3", "get")

      -- assertions
      assert.are.equal(headers["access-control-allow-origin"], "*")
      assert.are.equal(headers["access-control-allow-methods"], nil)
      assert.are.equal(headers["access-control-allow-headers"], nil)
      assert.are.equal(headers["access-control-expose-headers"], nil)
      assert.are.equal(headers["access-control-allow-credentials"], nil)
      assert.are.equal(headers["access-control-max-age"], nil)
    end)

    it("should reflect some of what is specified in options", function()
      local options = {}

      -- setup options
      options["value.origin"] = "example.com"
      options["value.methods"] = "GET"
      options["value.headers"] = "origin, type, accepts"
      options["value.exposed_headers"] = "x-auth-token"
      options["value.max_age"] = 23
      options["value.credentials"] = true

      -- enable plugin
      enable_plugin("API_TESTS_4", "cors", options)

      -- make proxy request
      local response, status, headers = request("API_TESTS_4", "get")

      -- assertions
      assert.are.equal(headers["access-control-allow-origin"], options["value.origin"])
      assert.are.equal(headers["access-control-expose-headers"], options["value.exposed_headers"])
      assert.are.equal(headers["access-control-allow-headers"], nil)
      assert.are.equal(headers["access-control-allow-methods"], nil)
      assert.are.equal(headers["access-control-max-age"], nil)
      assert.are.equal(headers["access-control-allow-credentials"], "true")
    end)
  end)
end)