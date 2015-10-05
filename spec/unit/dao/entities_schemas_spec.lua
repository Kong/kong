local api_schema = require "kong.dao.schemas.apis"
local consumer_schema = require "kong.dao.schemas.consumers"
local plugins_schema = require "kong.dao.schemas.plugins"
local validations = require "kong.dao.schemas_validation"
local validate_entity = validations.validate_entity

require "kong.tools.ngx_stub"

describe("Entities Schemas", function()

  for k, schema in pairs({api = api_schema,
                          consumer = consumer_schema,
                          plugins = plugins_schema}) do
    it(k.." schema should have some required properties", function()
      assert.truthy(schema.name)
      assert.equal("string", type(schema.name))

      assert.truthy(schema.primary_key)
      assert.equal("table", type(schema.primary_key))

      assert.truthy(schema.fields)
      assert.equal("table", type(schema.fields))
    end)
  end

  describe("APIs", function()

    it("should refuse an empty object", function()
      local valid, errors = validate_entity({}, api_schema)
      assert.False(valid)
      assert.truthy(errors)
    end)

    it("should return error with wrong upstream_url", function()
      local valid, errors = validate_entity({
        request_host = "mockbin.com",
        upstream_url = "asdasd"
      }, api_schema)
      assert.False(valid)
      assert.equal("upstream_url is not a url", errors.upstream_url)
    end)

    it("should return error with wrong upstream_url protocol", function()
      local valid, errors = validate_entity({
        request_host = "mockbin.com",
        upstream_url = "wot://mockbin.com/"
      }, api_schema)
      assert.False(valid)
      assert.equal("Supported protocols are HTTP and HTTPS", errors.upstream_url)
    end)

    it("should validate without a request_path", function()
      local valid, errors = validate_entity({
        request_host = "mockbin.com",
        upstream_url = "http://mockbin.com"
      }, api_schema)
      assert.falsy(errors)
      assert.True(valid)
    end)

    it("should validate with upper case protocol", function()
      local valid, errors = validate_entity({
        request_host = "mockbin.com",
        upstream_url = "HTTP://mockbin.com/world"
      }, api_schema)
      assert.falsy(errors)
      assert.True(valid)
    end)

    it("should complain if missing `request_host` and `request_path`", function()
      local valid, errors = validate_entity({
        name = "mockbin"
      }, api_schema)
      assert.False(valid)
      assert.equal("At least a 'request_host' or a 'request_path' must be specified", errors.request_path)
      assert.equal("At least a 'request_host' or a 'request_path' must be specified", errors.request_host)

      local valid, errors = validate_entity({
        name = "mockbin",
        request_path = true
      }, api_schema)
      assert.False(valid)
      assert.equal("request_path is not a string", errors.request_path)
      assert.equal("At least a 'request_host' or a 'request_path' must be specified", errors.request_host)
    end)

    it("should set the name from request_host if not set", function()
      local t = {request_host = "mockbin.com", upstream_url = "http://mockbin.com"}

      local valid, errors = validate_entity(t, api_schema)
      assert.falsy(errors)
      assert.True(valid)
      assert.equal("mockbin.com", t.name)
    end)

    it("should set the name from request_path if not set", function()
      local t = {request_path = "/mockbin", upstream_url = "http://mockbin.com"}

      local valid, errors = validate_entity(t, api_schema)
      assert.falsy(errors)
      assert.True(valid)
      assert.equal("mockbin", t.name)
    end)

    it("should not accept a name with reserved URI characters in it", function()
      for _, name in ipairs({"mockbin#2", "mockbin/com", "mockbin\"", "mockbin:2", "mockbin?", "[mockbin]"}) do
        local t = {name = name, upstream_url = "http://mockbin.com", request_host = "mockbin.com"}

        local valid, errors = validate_entity(t, api_schema)
        assert.False(valid)
        assert.truthy(errors)
        assert.equal("name must only contain alphanumeric and '., -, _, ~' characters", errors.name)
      end
    end)

    it("should normalize a name for URI if coming from request_host or request_path", function()
      local t = {upstream_url = "http://mockbin.com", request_host = "mockbin#com"}

      local valid, errors = validate_entity(t, api_schema)
      assert.True(valid)
      assert.falsy(errors)
      assert.equal("mockbin-com", t.name)

      t = {upstream_url = "http://mockbin.com", request_path = "/mockbin/status"}

      valid, errors = validate_entity(t, api_schema)
      assert.True(valid)
      assert.falsy(errors)
      assert.equal("mockbin-status", t.name)
    end)

    it("should accept valid wildcard request_host", function()
      local valid, errors = validate_entity({
        name = "mockbin",
        request_host = "*.mockbin.org",
        upstream_url = "http://mockbin.com"
      }, api_schema)
      assert.True(valid)
      assert.falsy(errors)

      valid, errors = validate_entity({
        name = "mockbin",
        request_host = "mockbin.*",
        upstream_url = "http://mockbin.com"
      }, api_schema)
      assert.True(valid)
      assert.falsy(errors)
    end)

    it("should refuse invalid wildcard request_host", function()
      local api_t = {
        name = "mockbin",
        request_host = "*.mockbin.*",
        upstream_url = "http://mockbin.com"
      }

      local valid, errors = validate_entity(api_t, api_schema)
      assert.False(valid)
      assert.equal("Only one wildcard is allowed: *.mockbin.*", errors.request_host)

      api_t.request_host = "*mockbin.com"
      valid, errors = validate_entity(api_t, api_schema)
      assert.False(valid)
      assert.equal("Invalid wildcard placement: *mockbin.com", errors.request_host)

      api_t.request_host = "www.mockbin*"
      valid, errors = validate_entity(api_t, api_schema)
      assert.False(valid)
      assert.equal("Invalid wildcard placement: www.mockbin*", errors.request_host)
    end)

    it("should only accept alphanumeric `request_path`", function()
      local valid, errors = validate_entity({
        name = "mockbin",
        request_path = "/[a-zA-Z]{3}",
        upstream_url = "http://mockbin.com"
      }, api_schema)
      assert.equal("request_path must only contain alphanumeric and '., -, _, ~, /' characters", errors.request_path)
      assert.False(valid)

      valid = validate_entity({
        name = "mockbin",
        request_path = "/status/",
        upstream_url = "http://mockbin.com"
      }, api_schema)
      assert.True(valid)

      valid = validate_entity({
        name = "mockbin",
        request_path = "/abcd~user-2",
        upstream_url = "http://mockbin.com"
      }, api_schema)
      assert.True(valid)
    end)

    it("should prefix a `request_path` with a slash and remove trailing slash", function()
      local api_t = { name = "mockbin", request_path = "status", upstream_url = "http://mockbin.com" }
      validate_entity(api_t, api_schema)
      assert.equal("/status", api_t.request_path)

      api_t.request_path = "/status"
      validate_entity(api_t, api_schema)
      assert.equal("/status", api_t.request_path)

      api_t.request_path = "status/"
      validate_entity(api_t, api_schema)
      assert.equal("/status", api_t.request_path)

      api_t.request_path = "/status/"
      validate_entity(api_t, api_schema)
      assert.equal("/status", api_t.request_path)

      api_t.request_path = "/deep/nested/status/"
      validate_entity(api_t, api_schema)
      assert.equal("/deep/nested/status", api_t.request_path)

      api_t.request_path = "deep/nested/status"
      validate_entity(api_t, api_schema)
      assert.equal("/deep/nested/status", api_t.request_path)

      -- Strip all leading slashes
      api_t.request_path = "//deep/nested/status"
      validate_entity(api_t, api_schema)
      assert.equal("/deep/nested/status", api_t.request_path)

      -- Strip all trailing slashes
      api_t.request_path = "/deep/nested/status//"
      validate_entity(api_t, api_schema)
      assert.equal("/deep/nested/status", api_t.request_path)

      -- Error if invalid request_path
      api_t.request_path = "/deep//nested/status"
      local _, errors = validate_entity(api_t, api_schema)
      assert.equal("request_path is invalid: /deep//nested/status", errors.request_path)
    end)

  end)

  describe("Consumers", function()

    it("should require a `custom_id` or `username`", function()
      local valid, errors = validate_entity({}, consumer_schema)
      assert.False(valid)
      assert.equal("At least a 'custom_id' or a 'username' must be specified", errors.username)
      assert.equal("At least a 'custom_id' or a 'username' must be specified", errors.custom_id)

      valid, errors = validate_entity({ username = "" }, consumer_schema)
      assert.False(valid)
      assert.equal("At least a 'custom_id' or a 'username' must be specified", errors.username)
      assert.equal("At least a 'custom_id' or a 'username' must be specified", errors.custom_id)

      valid, errors = validate_entity({ username = true }, consumer_schema)
      assert.False(valid)
      assert.equal("username is not a string", errors.username)
      assert.equal("At least a 'custom_id' or a 'username' must be specified", errors.custom_id)
    end)

  end)

  describe("Plugins Configurations", function()

    local dao_stub = {
      plugins = {
        find_by_keys = function()
          return nil
        end
      }
    }

    it("should not validate if the plugin doesn't exist (not installed)", function()
      local valid, errors = validate_entity({name = "world domination"}, plugins_schema)
      assert.False(valid)
      assert.equal("Plugin \"world domination\" not found", errors.config)
    end)

    it("should validate a plugin configuration's `config` field", function()
      -- Success
      local plugin = {name = "key-auth", api_id = "stub", config = {key_names = {"x-kong-key"}}}
      local valid = validate_entity(plugin, plugins_schema, {dao = dao_stub})
      assert.True(valid)

      -- Failure
      plugin = {name = "rate-limiting", api_id = "stub", config = { second = "hello" }}

      local valid, errors = validate_entity(plugin, plugins_schema, {dao = dao_stub})
      assert.False(valid)
      assert.equal("second is not a number", errors["config.second"])
    end)

    it("should have an empty config if none is specified and if the config schema does not have default", function()
      -- Insert key-auth, whose config has some default values that should be set
      local plugin = {name = "key-auth", api_id = "stub"}
      local valid = validate_entity(plugin, plugins_schema, {dao = dao_stub})
      assert.same({key_names = {"apikey"}, hide_credentials = false}, plugin.config)
      assert.True(valid)

      -- Insert reauest-transformer, whose default config has no default values, and should be empty
      local plugin2 = {name = "response-transformer", api_id = "stub"}
      valid = validate_entity(plugin2, plugins_schema, {dao = dao_stub})
      assert.same({}, plugin2.config)
      assert.True(valid)
    end)

    describe("self_check", function()
      it("should refuse `consumer_id` if specified in the config schema", function()
        local stub_config_schema = {
          no_consumer = true,
          fields = {
            string = {type = "string", required = true}
          }
        }

        plugins_schema.fields.config.schema = function()
          return stub_config_schema
        end

        local valid, _, err = validate_entity({name = "stub", api_id = "0000", consumer_id = "0000", config = {string = "foo"}}, plugins_schema)
        assert.False(valid)
        assert.equal("No consumer can be configured for that plugin", err.message)

        valid, err = validate_entity({name = "stub", api_id = "0000", config = {string = "foo"}}, plugins_schema, {dao = dao_stub})
        assert.True(valid)
        assert.falsy(err)
      end)
    end)
  end)
end)
