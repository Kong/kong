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
      assert.is_table(schema.primary_key)
      assert.is_table(schema.fields)
      assert.is_string(schema.table)
    end)
  end

  --
  -- API
  --

  describe("APIs", function()
    it("should refuse an empty object", function()
      local valid, errors = validate_entity({}, api_schema)
      assert.False(valid)
      assert.truthy(errors)
    end)

    describe("name", function()
      it("should not accept a name with reserved URI characters in it", function()
        for _, name in ipairs({"mockbin#2", "mockbin/com", "mockbin\"", "mockbin:2", "mockbin?", "[mockbin]"}) do
          local t = {name = name, upstream_url = "http://mockbin.com", request_host = "mockbin.com"}

          local valid, errors = validate_entity(t, api_schema)
          assert.False(valid)
          assert.truthy(errors)
          assert.equal("name must only contain alphanumeric and '., -, _, ~' characters", errors.name)
        end
      end)
    end)

    describe("upstream_url", function()
      it("should return error with wrong upstream_url", function()
        local valid, errors = validate_entity({
          name = "mockbin",
          request_host = "mockbin.com",
          upstream_url = "asdasd"
        }, api_schema)
        assert.False(valid)
        assert.equal("upstream_url is not a url", errors.upstream_url)
      end)
      it("should return error with wrong upstream_url protocol", function()
        local valid, errors = validate_entity({
          name = "mockbin",
          request_host = "mockbin.com",
          upstream_url = "wot://mockbin.com/"
        }, api_schema)
        assert.False(valid)
        assert.equal("Supported protocols are HTTP and HTTPS", errors.upstream_url)
      end)
      it("should validate with upper case protocol", function()
        local valid, errors = validate_entity({
          name = "mockbin",
          request_host = "mockbin.com",
          upstream_url = "HTTP://mockbin.com/world"
        }, api_schema)
        assert.falsy(errors)
        assert.True(valid)
      end)
    end)

    describe("request_host", function()
      it("should complain if it is an empty string", function()
        local t = {request_host = "", upstream_url = "http://mockbin.com", name = "mockbin"}

        local valid, errors = validate_entity(t, api_schema)
        assert.False(valid)
        assert.equal("At least a 'request_host' or a 'request_path' must be specified", errors.request_host)
        assert.equal("At least a 'request_host' or a 'request_path' must be specified", errors.request_path)
      end)
      it("should not accept an invalid request_host", function()
        local invalids = {"/mockbin", ".mockbin", "mockbin.", "mockbin.f", "mock;bin",
                          "mockbin.com-org", "mockbin.com/org", "mockbin.com_org",
                          "-mockbin.org", "mockbin-.org", "mockbin.or-g", "mockbin.org-",
                          "mockbin.-org", "hello.-mockbin.com", "hello..mockbin.com", "hello-.mockbin.com"}

        for _, v in ipairs(invalids) do
          local t = {request_host = v, upstream_url = "http://mockbin.com", name = "mockbin"}
          local valid, errors = validate_entity(t, api_schema)
          assert.equal("Invalid value: "..v, (errors and errors.request_host or ""))
          assert.falsy(errors.request_path)
          assert.False(valid)
        end
      end)
      it("should accept valid request_host", function()
        local valids = {"hello.com", "hello.fr", "test.hello.com", "1991.io", "hello.COM",
                        "HELLO.com", "123helloWORLD.com", "mockbin.123", "mockbin-api.com",
                        "hello.abcd", "mockbin_api.com"}

        for _, v in ipairs(valids) do
          local t = {request_host = v, upstream_url = "http://mockbin.com", name = "mockbin"}
          local valid, errors = validate_entity(t, api_schema)
          assert.falsy(errors)
          assert.True(valid)
        end
      end)
      it("should accept valid wildcard request_host", function()
        local valids = {"mockbin.*", "*.mockbin.org"}

        for _, v in ipairs(valids) do
          local t = {request_host = v, upstream_url = "http://mockbin.com", name = "mockbin"}
          local valid, errors = validate_entity(t, api_schema)
          assert.falsy(errors)
          assert.True(valid)
        end
      end)
      it("should refuse request_host with more than one wildcard", function()
        local api_t = {
          name = "mockbin",
          request_host = "*.mockbin.*",
          upstream_url = "http://mockbin.com"
        }

        local valid, errors = validate_entity(api_t, api_schema)
        assert.False(valid)
        assert.equal("Only one wildcard is allowed: *.mockbin.*", errors.request_host)
      end)
      it("should refuse invalid wildcard request_host", function()
        local invalids = {"*mockbin.com", "www.mockbin*", "mock*bin.com"}

        for _, v in ipairs(invalids) do
          local t = {request_host = v, upstream_url = "http://mockbin.com", name = "mockbin"}
          local valid, errors = validate_entity(t, api_schema)
          assert.equal("Invalid wildcard placement: "..v, (errors and errors.request_host or ""))
          assert.False(valid)
        end
      end)
    end)

    describe("request_path", function()
      it("should complain if it is an empty string", function()
        local t = {request_path = "", upstream_url = "http://mockbin.com"}

        local valid, errors = validate_entity(t, api_schema)
        assert.False(valid)
        assert.equal("At least a 'request_host' or a 'request_path' must be specified", errors.request_host)
        assert.equal("At least a 'request_host' or a 'request_path' must be specified", errors.request_path)
      end)
      it("should not accept reserved characters from RFC 3986", function()
        local invalids = {"/[a-z]{3}"}

        for _, v in ipairs(invalids) do
          local t = {request_path = v, upstream_url = "http://mockbin.com", name = "mockbin"}
          local valid, errors = validate_entity(t, api_schema)
          assert.False(valid)
          assert.equal("must only contain alphanumeric and '., -, _, ~, /' characters", errors.request_path)
        end
      end)
      it("should accept unreserved characters from RFC 3986", function()
        local valids = {"/abcd~user-2"}

        for _, v in ipairs(valids) do
          local t = {request_path = v, upstream_url = "http://mockbin.com", name = "mockbin"}
          local valid, errors = validate_entity(t, api_schema)
          assert.falsy(errors)
          assert.True(valid)
        end
      end)
      it("should not accept without prefix slash", function()
        local invalids = {"status", "status/123"}

        for _, v in ipairs(invalids) do
          local t = {request_path = v, upstream_url = "http://mockbin.com", name = "mockbin"}
          local valid, errors = validate_entity(t, api_schema)
          assert.False(valid)
          assert.equal("must be prefixed with slash: '"..v.."'", errors.request_path)
        end
      end)
      it("should accept root (prefix slash)", function()
        local valid, errors = validate_entity({
          name = "mockbin",
          request_path = "/",
          upstream_url = "http://mockbin.com"
        }, api_schema)
        assert.falsy(errors)
        assert.True(valid)
      end)
      it("should not accept invalid URI", function()
        local invalids = {"//status", "/status//123", "/status/123//"}

        for _, v in ipairs(invalids) do
          local t = {request_path = v, upstream_url = "http://mockbin.com", name = "mockbin"}
          local valid, errors = validate_entity(t, api_schema)
          assert.False(valid)
          assert.equal("invalid: '"..v.."'", errors.request_path)
        end
      end)
      it("should remove trailing slash", function()
        local valids = {"/status/", "/status/123/"}

        for _, v in ipairs(valids) do
          local t = {request_path = v, upstream_url = "http://mockbin.com", name = "mockbin"}
          local valid, errors = validate_entity(t, api_schema)
          assert.falsy(errors)
          assert.equal(string.sub(v, 1, -2), t.request_path)
          assert.True(valid)
        end
      end)
    end)

    it("should validate without a request_path", function()
      local valid, errors = validate_entity({
        request_host = "mockbin.com",
        upstream_url = "http://mockbin.com"
      }, api_schema)
      assert.falsy(errors)
      assert.True(valid)
    end)

    it("should complain if missing request_host and request_path", function()
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

    it("should normalize a name for URI if coming from request_host or request_path", function()
      local t = {upstream_url = "http://mockbin.com", request_host = "mockbin.com"}

      local valid, errors = validate_entity(t, api_schema)
      assert.True(valid)
      assert.falsy(errors)
      assert.equal("mockbin.com", t.name)

      t = {upstream_url = "http://mockbin.com", request_path = "/mockbin/status"}

      valid, errors = validate_entity(t, api_schema)
      assert.True(valid)
      assert.falsy(errors)
      assert.equal("mockbin-status", t.name)
    end)
  end)

  --
  -- Consumer
  --

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

  --
  -- Plugins
  --

  describe("Plugins Configurations", function()

    local dao_stub = {
      find_all = function()
        return {}
      end
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
    end)
    it("should be valid if no value is specified for a subfield and if the config schema has default as empty array", function()
      -- Insert response-transformer, whose default config has no default values, and should be empty
      local plugin2 = {name = "response-transformer", api_id = "stub"}
      local valid = validate_entity(plugin2, plugins_schema, {dao = dao_stub})
      assert.same({
        remove = {
          headers = {},
          json = {}
        },
        replace = {
          headers = {},
          json = {}
        },
        add = {
          headers = {},
          json = {}
        },
        append = {
          headers = {},
          json = {}
        }
      }, plugin2.config)
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

  describe("update", function()
    it("should only validate updated fields", function()
      local t = {request_host = "", upstream_url = "http://mockbin.com"}

      local valid, errors = validate_entity(t, api_schema, {
        update = true
      })
      assert.False(valid)
      assert.same({
        request_host = "At least a 'request_host' or a 'request_path' must be specified"
      }, errors)
    end)
  end)
end)
