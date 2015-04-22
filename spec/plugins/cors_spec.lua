local spec_helper = require "spec.spec_helpers"
local http_client = require "kong.tools.http_client"
local cjson = require "cjson"

local APIS = {}
local PLUGINS = {}
local API_URL = spec_helper.API_URL
local PROXY_URL = spec_helper.PROXY_URL

function request (method, qs, headers)
  headers = merge({ host = "mockbin.com" }, headers)
  return http_client[method](PROXY_URL, qs, { host = "mockbin.com" })
end

function create_api (name)
  local response, status, headers = http_client.post(API_URL.."/apis/", { name=name, target_url="http://mockbin.com", public_dns="mockbin.com" }, {})

  -- decode response
  response = cjson.decode(response)

  -- store id for later usage
  APIS[name] = response.id
end

function delete_api (name)
  local response, status, headers = http_client.delete(API_URL.."/apis/"..get_id(name))

  -- remove api if we obtain 200
  if status == 200 then
    APIS[name] = nil
  end

  -- ensure api has been deleted
  assert.are.equal(get_id(name), nil)
end

function delete_apis ()
  for name, id in pairs(APIS) do http_client.delete(API_URL.."/apis/"..id) end
  APIS = {}
end

function enable_plugin (api_name, name, options)
  local plugin = merge({ name=name, api_id=get_id(api_name) }, options or {})
  local response, status, headers = http_client.post(API_URL.."/plugins_configurations/", plugin)

  -- decode response
  response = cjson.decode(response)

  -- store for later usage
  table.insert(PLUGINS, response.id)

  -- return results
  return response, status, headers
end

function delete_plugins ()
  for i, id in ipairs(PLUGINS) do http_client.delete(API_URL.."/plugins_configurations/"..id) end
  PLUGINS = {}
end

function get_id (name)
  return APIS[name]
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

    create_api("API_TESTS_1")
  end)

  teardown(function()
    spec_helper.stop_kong()
    spec_helper.reset_db()
  end)

  describe("Schema", function()
    it("should set the appropriate defaults", function()
      local response, status, headers = enable_plugin("API_TESTS_1", "cors")

      -- assertions
      assert.are.equal(status, 201)
      assert.are.equal(response.value.preflight_continue, false)
      assert.are.equal(response.value.allow_credentials, false)
      assert.are.equal(response.value.methods, nil)
      assert.are.equal(response.value.headers, nil)
      assert.are.equal(response.value.max_age, nil)
      assert.are.equal(response.value.origin, nil)

      -- cleanup
      delete_plugins()
    end)

    it("should ignore values outside of the schema", function()
      local options = { values={ testing="invalid" } }
      local response, status, headers = enable_plugin("API_TESTS_1", "cors", options)

      -- assertions
      assert.are.equal(status, 201)
      assert.falsy(response.value.testing)

      -- cleanup
      delete_plugins()
    end)
  end)

  describe("Access-Control-Allow-Origin", function()
    before_each(function()
      enable_plugin("API_TESTS_1", "cors")
    end)

    it("should be * by default without any options passed", function()
      -- make request
      local response, status, headers = request("options", nil, { origin = "testing.com" })

      -- assertions
      assert.are.equal(status, 204)

      -- cleanup
      delete_plugins()
    end)
  end)
end)