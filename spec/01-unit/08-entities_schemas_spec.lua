local api_schema = require "kong.dao.schemas.apis"
local consumer_schema = require "kong.dao.schemas.consumers"
local plugins_schema = require "kong.dao.schemas.plugins"
local validations = require "kong.dao.schemas_validation"
local validate_entity = validations.validate_entity

--require "kong.tools.ngx_stub"

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
      it("is required", function()
        local t = {}

        local ok, errors = validate_entity(t, api_schema)
        assert.False(ok)
        assert.equal("name is required", errors.name)
      end)

      it("should not accept a name with reserved URI characters in it", function()
        for _, name in ipairs({"mockbin#2", "mockbin/com", "mockbin\"", "mockbin:2", "mockbin?", "[mockbin]"}) do
          local t = {
            name = name,
            upstream_url = "http://mockbin.com",
            hosts = { "mockbin.com" }
          }

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
          upstream_url = "asdasd",
          hosts = { "mockbin.com" },
        }, api_schema)
        assert.False(valid)
        assert.equal("upstream_url is not a url", errors.upstream_url)
      end)

      it("should return error with wrong upstream_url protocol", function()
        local valid, errors = validate_entity({
          name = "mockbin",
          upstream_url = "wot://mockbin.com/",
          hosts = { "mockbin.com" },
        }, api_schema)
        assert.False(valid)
        assert.equal("Supported protocols are HTTP and HTTPS", errors.upstream_url)

      end)
      it("should validate with upper case protocol", function()
        local valid, errors = validate_entity({
          name = "mockbin",
          upstream_url = "HTTP://mockbin.com/world",
          hosts = { "mockbin.com" },
        }, api_schema)
        assert.falsy(errors)
        assert.True(valid)
      end)
    end)

    describe("hosts", function()
      it("accepts an array", function()
        local t = {
          name = "httpbin",
          upstream_url = "http://httpbin.org",
          hosts = { "httpbin.org" },
        }

        local ok, errors = validate_entity(t, api_schema)
        assert.True(ok)
        assert.is_nil(errors)
      end)

      it("accepts valid hosts", function()
        local valids = {"hello.com", "hello.fr", "test.hello.com", "1991.io", "hello.COM",
                        "HELLO.com", "123helloWORLD.com", "mockbin.123", "mockbin-api.com",
                        "hello.abcd", "mockbin_api.com", "localhost",
                        -- punycode examples from RFC3492; https://tools.ietf.org/html/rfc3492#page-14
                        -- specifically the japanese ones as they mix ascii with escaped characters
                        "3B-ww4c5e180e575a65lsy2b", "-with-SUPER-MONKEYS-pc58ag80a8qai00g7n9n",
                        "Hello-Another-Way--fc4qua05auwb3674vfr0b", "2-u9tlzr9756bt3uc0v",
                        "MajiKoi5-783gue6qz075azm5e", "de-jg4avhby1noc0d", "d9juau41awczczp",
                        }

        for _, v in ipairs(valids) do
          local t = {
            name = "mockbin",
            upstream_url = "http://mockbin.com",
            hosts = { v },
          }

          local ok, errors = validate_entity(t, api_schema)
          assert.True(ok)
          assert.is_nil(errors)
        end
      end)

      it("accepts hosts with valid wildcard", function()
        local valids = {"mockbin.*", "*.mockbin.org"}

        for _, v in ipairs(valids) do
          local t = {
            name = "mockbin",
            upstream_url = "http://mockbin.com",
            hosts = { v },
          }

          local ok, errors = validate_entity(t, api_schema)
          assert.True(ok)
          assert.is_nil(errors)
        end
      end)

      describe("errors", function()
        pending("rejects if not a table", function()
          -- pending: currently, schema_validation uses `split()` which creates
          -- a table containing { "mockbin.com" }, hence this test is not
          -- relevant.
          local t = {
            name = "mockbin",
            upstream_url = "http://mockbin.com",
            hosts = "mockbin.com",
          }

          local ok, errors = validate_entity(t, api_schema)
          assert.False(ok)
          assert.equal("not an array", errors.hosts)
        end)

        it("rejects values that are not strings", function()
          local t = {
            name = "mockbin",
            upstream_url = "http://mockbin.com",
            hosts = { 123 },
          }

          local ok, errors = validate_entity(t, api_schema)
          assert.False(ok)
          assert.equal("host with value '123' is invalid: must be a string", errors.hosts)
        end)

        it("rejects empty strings", function()
          local invalids = { "", "   " }

          for _, v in ipairs(invalids) do
            local t = {
              name = "mockbin",
              upstream_url = "http://mockbin.com",
              hosts = { v },
            }

            local ok, errors = validate_entity(t, api_schema)
            assert.False(ok)
            assert.matches("host is empty", errors.hosts, nil, true)
          end
        end)

        it("rejects invalid hosts", function()
          local invalids = {"/mockbin", ".mockbin", "mockbin.", "mock;bin",
                            "mockbin.com/org",
                            "mockbin-.org", "mockbin.org-",
                            "hello..mockbin.com", "hello-.mockbin.com"}

          for _, v in ipairs(invalids) do
            local t = {
              name = "mockbin",
              upstream_url = "http://mockbin.com",
              hosts = { v },
            }

            local ok, errors = validate_entity(t, api_schema)
            assert.False(ok)
            assert.matches("host with value '" .. v .. "' is invalid", errors.hosts, nil, true)
          end
        end)

        it("rejects invalid wildcard placement", function()
          local invalids = {"*mockbin.com", "www.mockbin*", "mock*bin.com"}

          for _, v in ipairs(invalids) do
            local t = {
              name = "mockbin",
              upstream_url = "http://mockbin.com",
              hosts = { v },
            }

            local ok, errors = validate_entity(t, api_schema)
            assert.False(ok)
            assert.matches("Invalid wildcard placement", errors.hosts, nil, true)
          end
        end)

        it("rejects host with too many wildcards", function()
          local api_t = {
            name = "mockbin",
            upstream_url = "http://mockbin.com",
            hosts = { "*.mockbin.*" },
          }

          local ok, errors = validate_entity(api_t, api_schema)
          assert.False(ok)
          assert.matches("Only one wildcard is allowed", errors.hosts)
        end)
      end)
    end)

    describe("uris", function()
      it("accepts correct uris", function()
        local t = {
          name = "httpbin",
          upstream_url = "http://httpbin.org",
          uris = { "/path" },
        }

        local ok, errors = validate_entity(t, api_schema)
        assert.is_nil(errors)
        assert.True(ok)
      end)

      it("accepts unreserved characters from RFC 3986", function()
        local t = {
          name = "httpbin",
          upstream_url = "http://httpbin.org",
          uris = { "/abcd~user~2" },
        }

        local ok, errors = validate_entity(t, api_schema)
        assert.is_nil(errors)
        assert.True(ok)
      end)

      it("accepts properly %-encoded characters", function()
        local valids = {"/abcd%aa%10%ff%AA%FF"}

        for _, v in ipairs(valids) do
          local t = {
            name = "mockbin",
            upstream_url = "http://mockbin.com",
            uris = { v },
          }

          local ok, errors = validate_entity(t, api_schema)
          assert.is_nil(errors)
          assert.True(ok)
        end
      end)

      it("accepts root (prefix slash)", function()
        local ok, errors = validate_entity({
          name = "mockbin",
          upstream_url = "http://mockbin.com",
          uris = { "/" },
        }, api_schema)

        assert.is_nil(errors)
        assert.True(ok)
      end)

      it("removes trailing slashes", function()
        local valids = {"/status/", "/status/123/"}

        for _, v in ipairs(valids) do
          local t = {
            name = "mockbin",
            upstream_url = "http://mockbin.com",
            uris = { v },
          }

          local ok, errors = validate_entity(t, api_schema)
          assert.is_nil(errors)
          assert.True(ok)
          assert.matches(string.sub(v, 1, -2), t.uris[1], nil, true)
        end
      end)

      describe("errors", function()
        it("rejects values that are not strings", function()
          local t = {
            name = "mockbin",
            upstream_url = "http://mockbin.com",
            uris = { 123 },
          }

          local ok, errors = validate_entity(t, api_schema)
          assert.False(ok)
          assert.equal("uri with value '123' is invalid: must be a string", errors.uris)
        end)

        it("rejects empty strings", function()
          local invalids = { "", "   " }

          for _, v in ipairs(invalids) do
            local t = {
              name = "mockbin",
              upstream_url = "http://mockbin.com",
              uris = { v },
            }

            local ok, errors = validate_entity(t, api_schema)
            assert.False(ok)
            assert.matches("uri is empty", errors.uris, nil, true)
          end
        end)

        it("rejects reserved characters from RFC 3986", function()
          local invalids = { "/[a-z]{3}" }

          for _, v in ipairs(invalids) do
            local t = {
              name = "mockbin",
              upstream_url = "http://mockbin.com",
              uris = { v },
            }

            local ok, errors = validate_entity(t, api_schema)
            assert.False(ok)
            assert.matches("must only contain alphanumeric and '., -, _, ~, /, %' characters", errors.uris, nil, true)
          end
        end)

        it("rejects bad %-encoded characters", function()
          local invalids = {
            "/some%2words",
            "/some%0Xwords",
            "/some%2Gwords",
            "/some%20words%",
            "/some%20words%a",
            "/some%20words%ax",
          }

          local errstr = { "%2w", "%0X", "%2G", "%", "%a", "%ax" }

          for i, v in ipairs(invalids) do
            local t = {
              name = "mockbin",
              upstream_url = "http://mockbin.com",
              uris = { v },
            }

            local ok, errors = validate_entity(t, api_schema)
            assert.False(ok)
            assert.matches("must use proper encoding; '"..errstr[i].."' is invalid", errors.uris, nil, true)
          end
        end)

        it("rejects uris without prefix slash", function()
          local invalids = {"status", "status/123"}

          for _, v in ipairs(invalids) do
            local t = {
              name = "mockbin",
              upstream_url = "http://mockbin.com",
              uris = { v },
            }

            local ok, errors = validate_entity(t, api_schema)
            assert.False(ok)
            assert.matches("must be prefixed with slash", errors.uris, nil, true)
          end
        end)

        it("rejects invalid URIs", function()
          local invalids = {"//status", "/status//123", "/status/123//"}

          for _, v in ipairs(invalids) do
            local t = {
              name = "mockbin",
              upstream_url = "http://mockbin.com",
              uris = { v },
            }

            local ok, errors = validate_entity(t, api_schema)
            assert.False(ok)
            assert.matches("invalid", errors.uris, nil, true)
          end
        end)
      end)
    end)

    describe("#o methods", function()
      it("accepts correct methods", function()
        local t = {
          name = "httpbin",
          upstream_url = "http://httpbin.org",
          methods = { "GET", "POST" },
        }

        local ok, errors = validate_entity(t, api_schema)
        assert.is_nil(errors)
        assert.True(ok)
      end)

      describe("errors", function()
        it("rejects values that are not strings", function()
          local t = {
            name = "mockbin",
            upstream_url = "http://mockbin.com",
            methods = { 123 },
          }

          local ok, errors = validate_entity(t, api_schema)
          assert.False(ok)
          assert.equal("method with value '123' is invalid: must be a string", errors.methods)
        end)

        it("rejects empty strings", function()
          local invalids = { "", "   " }

          for _, v in ipairs(invalids) do
            local t = {
              name = "mockbin",
              upstream_url = "http://mockbin.com",
              methods = { v },
            }

            local ok, errors = validate_entity(t, api_schema)
            assert.False(ok)
            assert.matches("method is empty", errors.methods, nil, true)
          end
        end)

        it("rejects invalid values", function()
          local invalids = { "HELLO WORLD", " GET", "get" }

          for _, v in ipairs(invalids) do
            local t = {
              name = "mockbin",
              upstream_url = "http://mockbin.com",
              methods = { v },
            }

            local ok, errors = validate_entity(t, api_schema)
            assert.False(ok)
            assert.matches("invalid value", errors.methods, nil, true)
          end
        end)
      end)
    end)

    describe("retries", function()
      it("accepts valid values", function()
        local valids = {0, 5, 100, 32767}
        for _, v in ipairs(valids) do
          local t = {
            name = "mockbin",
            upstream_url = "http://mockbin.com",
            hosts = { "mydomain.com" },
            retries = v,
          }

          local valid, errors = validate_entity(t, api_schema)
          assert.falsy(errors)
          assert.True(valid)
        end
      end)
      it("rejects invalid values", function()
        local valids = { -5, 32768}
        for _, v in ipairs(valids) do
          local t = {
            name = "mockbin",
            upstream_url = "http://mockbin.com",
            hosts = { "mydomain.com" },
            retries = v,
          }

          local valid, errors = validate_entity(t, api_schema)
          assert.False(valid)
          assert.equal("retries must be an integer, from 0 to 32767", errors.retries)
        end
      end)
    end)

    it("should complain if no [hosts] or [uris] or [methods]", function()
      local ok, errors = validate_entity({
        name = "httpbin",
        upstream_url = "http://httpbin.org",
      }, api_schema)
      assert.False(ok)
      assert.same({
        hosts = "at least one of 'hosts', 'uris' or 'methods' must be specified",
        uris = "at least one of 'hosts', 'uris' or 'methods' must be specified",
        methods = "at least one of 'hosts', 'uris' or 'methods' must be specified",
      }, errors)
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
      assert.same({key_names = {"apikey"}, hide_credentials = false, anonymous = false}, plugin.config)
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
      -- does not complain about the missing "name" field

      local t = {
        upstream_url = "http://mockbin.com",
        hosts = { "" },
      }

      local ok, errors = validate_entity(t, api_schema, {
        update = true
      })
      assert.False(ok)
      assert.same({
        hosts = "host with value '' is invalid: host is empty"
      }, errors)
    end)
  end)
end)
