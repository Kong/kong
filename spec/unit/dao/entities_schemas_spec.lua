local api_schema = require "kong.dao.schemas.apis"
local consumer_schema = require "kong.dao.schemas.consumers"
local plugins_configurations_schema = require "kong.dao.schemas.plugins_configurations"
local validations = require "kong.dao.schemas_validation"
local validate_entity = validations.validate_entity

require "kong.tools.ngx_stub"

describe("Entities Schemas", function()

  for k, schema in pairs({api = api_schema,
                          consumer = consumer_schema,
                          plugins_configurations = plugins_configurations_schema}) do
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

    it("should return error with wrong target_url", function()
      local valid, errors = validate_entity({
        public_dns = "mockbin.com",
        target_url = "asdasd"
      }, api_schema)
      assert.False(valid)
      assert.equal("Invalid target URL", errors.target_url)
    end)

    it("should return error with wrong target_url protocol", function()
      local valid, errors = validate_entity({
        public_dns = "mockbin.com",
        target_url = "wot://mockbin.com/"
      }, api_schema)
      assert.False(valid)
      assert.equal("Supported protocols are HTTP and HTTPS", errors.target_url)
    end)

    it("should validate without a path", function()
      local valid, errors = validate_entity({
        public_dns = "mockbin.com",
        target_url = "http://mockbin.com"
      }, api_schema)
      assert.falsy(errors)
      assert.True(valid)
    end)

    it("should validate with upper case protocol", function()
      local valid, errors = validate_entity({
        public_dns = "mockbin.com",
        target_url = "HTTP://mockbin.com/world"
      }, api_schema)
      assert.falsy(errors)
      assert.True(valid)
    end)

    it("should complain if missing `public_dns` and `path`", function()
      local valid, errors = validate_entity({
        name = "mockbin"
      }, api_schema)
      assert.False(valid)
      assert.equal("At least a 'public_dns' or a 'path' must be specified", errors.path)
      assert.equal("At least a 'public_dns' or a 'path' must be specified", errors.public_dns)

      local valid, errors = validate_entity({
        name = "mockbin",
        path = true
      }, api_schema)
      assert.False(valid)
      assert.equal("path is not a string", errors.path)
      assert.equal("At least a 'public_dns' or a 'path' must be specified", errors.public_dns)
    end)

    it("should set the name from public_dns if not set", function()
      local t = { public_dns = "mockbin.com", target_url = "http://mockbin.com" }

      local valid, errors = validate_entity(t, api_schema)
      assert.falsy(errors)
      assert.True(valid)
      assert.equal("mockbin.com", t.name)
    end)

    it("should accept valid wildcard public_dns", function()
      local valid, errors = validate_entity({
        name = "mockbin",
        public_dns = "*.mockbin.org",
        target_url = "http://mockbin.com"
      }, api_schema)
      assert.True(valid)
      assert.falsy(errors)

      valid, errors = validate_entity({
        name = "mockbin",
        public_dns = "mockbin.*",
        target_url = "http://mockbin.com"
      }, api_schema)
      assert.True(valid)
      assert.falsy(errors)
    end)

    it("should refuse invalid wildcard public_dns", function()
      local api_t = {
        name = "mockbin",
        public_dns = "*.mockbin.*",
        target_url = "http://mockbin.com"
      }

      local valid, errors = validate_entity(api_t, api_schema)
      assert.False(valid)
      assert.equal("Only one wildcard is allowed: *.mockbin.*", errors.public_dns)

      api_t.public_dns = "*mockbin.com"
      valid, errors = validate_entity(api_t, api_schema)
      assert.False(valid)
      assert.equal("Invalid wildcard placement: *mockbin.com", errors.public_dns)

      api_t.public_dns = "www.mockbin*"
      valid, errors = validate_entity(api_t, api_schema)
      assert.False(valid)
      assert.equal("Invalid wildcard placement: www.mockbin*", errors.public_dns)
    end)

    it("should only accept alphanumeric `path`", function()
      local valid, errors = validate_entity({
        name = "mockbin",
        path = "/[a-zA-Z]{3}",
        target_url = "http://mockbin.com"
      }, api_schema)
      assert.equal("path must only contain alphanumeric and '. -, _, ~, /' characters", errors.path)
      assert.False(valid)

      valid = validate_entity({
        name = "mockbin",
        path = "/status/",
        target_url = "http://mockbin.com"
      }, api_schema)
      assert.True(valid)

      valid = validate_entity({
        name = "mockbin",
        path = "/abcd~user-2",
        target_url = "http://mockbin.com"
      }, api_schema)
      assert.True(valid)
    end)

    it("should prefix a `path` with a slash and remove trailing slash", function()
      local api_t = { name = "mockbin", path = "status", target_url = "http://mockbin.com" }
      validate_entity(api_t, api_schema)
      assert.equal("/status", api_t.path)

      api_t.path = "/status"
      validate_entity(api_t, api_schema)
      assert.equal("/status", api_t.path)

      api_t.path = "status/"
      validate_entity(api_t, api_schema)
      assert.equal("/status", api_t.path)

      api_t.path = "/status/"
      validate_entity(api_t, api_schema)
      assert.equal("/status", api_t.path)

      api_t.path = "/deep/nested/status/"
      validate_entity(api_t, api_schema)
      assert.equal("/deep/nested/status", api_t.path)

      api_t.path = "deep/nested/status"
      validate_entity(api_t, api_schema)
      assert.equal("/deep/nested/status", api_t.path)

      -- Strip all leading slashes
      api_t.path = "//deep/nested/status"
      validate_entity(api_t, api_schema)
      assert.equal("/deep/nested/status", api_t.path)

      -- Strip all trailing slashes
      api_t.path = "/deep/nested/status//"
      validate_entity(api_t, api_schema)
      assert.equal("/deep/nested/status", api_t.path)

      -- Error if invalid path
      api_t.path = "/deep//nested/status"
      local _, errors = validate_entity(api_t, api_schema)
      assert.equal("path is invalid: /deep//nested/status", errors.path)
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
      plugins_configurations = {
        find_by_keys = function()
          return nil
        end
      }
    }

    it("should not validate if the plugin doesn't exist (not installed)", function()
      local valid, errors = validate_entity({name = "world domination"}, plugins_configurations_schema)
      assert.False(valid)
      assert.equal("Plugin \"world domination\" not found", errors.value)
    end)

    it("should validate a plugin configuration's `value` field", function()
      -- Success
      local plugin = {name = "keyauth", api_id = "stub", value = {key_names = {"x-kong-key"}}}
      local valid = validate_entity(plugin, plugins_configurations_schema, {dao = dao_stub})
      assert.True(valid)

      -- Failure
      plugin = {name = "ratelimiting", api_id = "stub", value = {period = "hello"}}

      local valid, errors = validate_entity(plugin, plugins_configurations_schema, {dao = dao_stub})
      assert.False(valid)
      assert.equal("limit is required", errors["value.limit"])
      assert.equal("\"hello\" is not allowed. Allowed values are: \"second\", \"minute\", \"hour\", \"day\", \"month\", \"year\"", errors["value.period"])
    end)

    describe("self_check", function()
      it("should refuse `consumer_id` if specified in the value schema", function()
        local stub_value_schema = {
          no_consumer = true,
          fields = {
            string = {type = "string", required = true}
          }
        }

        plugins_configurations_schema.fields.value.schema = function()
          return stub_value_schema
        end

        local valid, _, err = validate_entity({name = "stub", api_id = "0000", consumer_id = "0000", value = {string = "foo"}}, plugins_configurations_schema)
        assert.False(valid)
        assert.equal("No consumer can be configured for that plugin", err.message)

        valid, err = validate_entity({name = "stub", api_id = "0000", value = {string = "foo"}}, plugins_configurations_schema, {dao = dao_stub})
        assert.True(valid)
        assert.falsy(err)
      end)
    end)
  end)
end)
