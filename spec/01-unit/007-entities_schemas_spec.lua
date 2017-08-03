local api_schema = require "kong.dao.schemas.apis"
local consumer_schema = require "kong.dao.schemas.consumers"
local plugins_schema = require "kong.dao.schemas.plugins"
local targets_schema = require "kong.dao.schemas.targets"
local upstreams_schema = require "kong.dao.schemas.upstreams"
local validations = require "kong.dao.schemas_validation"
local validate_entity = validations.validate_entity
local utils = require "kong.tools.utils"

describe("Entities Schemas", function()

  for k, schema in pairs({api = api_schema,
                          consumer = consumer_schema,
                          plugins = plugins_schema,
                          targets = targets_schema,
                          upstreams = upstreams_schema}) do
    it(k .. " schema should have some required properties", function()
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
      assert.is_false(valid)
      assert.truthy(errors)
    end)

    describe("name", function()
      it("is required", function()
        local t = {}

        local ok, errors = validate_entity(t, api_schema)
        assert.is_false(ok)
        assert.equal("name is required", errors.name)
      end)

      it("should not accept a name with reserved URI characters in it", function()
        for _, name in ipairs({"example#2", "example/com", "example\"", "example:2", "example?", "[example]"}) do
          local t = {
            name = name,
            upstream_url = "http://example.com",
            hosts = { "example.com" }
          }

          local valid, errors = validate_entity(t, api_schema)
          assert.is_false(valid)
          assert.truthy(errors)
          assert.equal("name must only contain alphanumeric and '., -, _, ~' characters", errors.name)
        end
      end)
    end)

    describe("upstream_url", function()
      it("should return error with wrong upstream_url", function()
        local valid, errors = validate_entity({
          name = "example",
          upstream_url = "asdasd",
          hosts = { "example.com" },
        }, api_schema)
        assert.is_false(valid)
        assert.equal("upstream_url is not a url", errors.upstream_url)
      end)

      it("should return error with wrong upstream_url protocol", function()
        local valid, errors = validate_entity({
          name = "example",
          upstream_url = "wot://example.com/",
          hosts = { "example.com" },
        }, api_schema)
        assert.is_false(valid)
        assert.equal("Supported protocols are HTTP and HTTPS", errors.upstream_url)
      end)

      it("should not return error with final slash in upstream_url", function()
        local valid, errors = validate_entity({
          name = "example",
          upstream_url = "http://example.com/",
          hosts = { "example.com" },
        }, api_schema)
        assert.is_nil(errors)
        assert.is_true(valid)
      end)

      it("should validate with upper case protocol", function()
        local valid, errors = validate_entity({
          name = "example",
          upstream_url = "HTTP://example.com/world",
          hosts = { "example.com" },
        }, api_schema)
        assert.falsy(errors)
        assert.is_true(valid)
      end)
    end)

    describe("hosts", function()
      it("accepts an array", function()
        local t = {
          name = "example",
          upstream_url = "http://example.org",
          hosts = { "example.org" },
        }

        local ok, errors = validate_entity(t, api_schema)
        assert.is_nil(errors)
        assert.is_true(ok)
      end)

      it("accepts valid hosts", function()
        local valids = {"hello.com", "hello.fr", "test.hello.com", "1991.io", "hello.COM",
                        "HELLO.com", "123helloWORLD.com", "example.123", "example-api.com",
                        "hello.abcd", "example_api.com", "localhost",
                        -- punycode examples from RFC3492; https://tools.ietf.org/html/rfc3492#page-14
                        -- specifically the japanese ones as they mix ascii with escaped characters
                        "3B-ww4c5e180e575a65lsy2b", "-with-SUPER-MONKEYS-pc58ag80a8qai00g7n9n",
                        "Hello-Another-Way--fc4qua05auwb3674vfr0b", "2-u9tlzr9756bt3uc0v",
                        "MajiKoi5-783gue6qz075azm5e", "de-jg4avhby1noc0d", "d9juau41awczczp",
                        }

        for _, v in ipairs(valids) do
          local t = {
            name = "example",
            upstream_url = "http://example.com",
            hosts = { v },
          }

          local ok, errors = validate_entity(t, api_schema)
          assert.is_nil(errors)
          assert.is_true(ok)
        end
      end)

      it("accepts hosts with valid wildcard", function()
        local valids = {"example.*", "*.example.org"}

        for _, v in ipairs(valids) do
          local t = {
            name = "example",
            upstream_url = "http://example.com",
            hosts = { v },
          }

          local ok, errors = validate_entity(t, api_schema)
          assert.is_nil(errors)
          assert.is_true(ok)
        end
      end)

      describe("errors", function()
        pending("rejects if not a table", function()
          -- pending: currently, schema_validation uses `split()` which creates
          -- a table containing { "example.com" }, hence this test is not
          -- relevant.
          local t = {
            name = "example",
            upstream_url = "http://example.com",
            hosts = "example.com",
          }

          local ok, errors = validate_entity(t, api_schema)
          assert.is_false(ok)
          assert.equal("not an array", errors.hosts)
        end)

        it("rejects values that are not strings", function()
          local t = {
            name = "example",
            upstream_url = "http://example.com",
            hosts = { 123 },
          }

          local ok, errors = validate_entity(t, api_schema)
          assert.is_false(ok)
          assert.equal("host with value '123' is invalid: must be a string", errors.hosts)
        end)

        it("rejects empty strings", function()
          local invalids = { "", "   " }

          for _, v in ipairs(invalids) do
            local t = {
              name = "example",
              upstream_url = "http://example.com",
              hosts = { v },
            }

            local ok, errors = validate_entity(t, api_schema)
            assert.is_false(ok)
            assert.matches("host is empty", errors.hosts, nil, true)
          end
        end)

        it("rejects invalid hosts", function()
          local invalids = {"/example", ".example", "example.", "mock;bin",
                            "example.com/org",
                            "example-.org", "example.org-",
                            "hello..example.com", "hello-.example.com"}

          for _, v in ipairs(invalids) do
            local t = {
              name = "example",
              upstream_url = "http://example.com",
              hosts = { v },
            }

            local ok, errors = validate_entity(t, api_schema)
            assert.is_false(ok)
            assert.matches("host with value '" .. v .. "' is invalid", errors.hosts, nil, true)
          end
        end)

        it("rejects invalid wildcard placement", function()
          local invalids = {"*example.com", "www.example*", "mock*bin.com"}

          for _, v in ipairs(invalids) do
            local t = {
              name = "example",
              upstream_url = "http://example.com",
              hosts = { v },
            }

            local ok, errors = validate_entity(t, api_schema)
            assert.is_false(ok)
            assert.matches("Invalid wildcard placement", errors.hosts, nil, true)
          end
        end)

        it("rejects host with too many wildcards", function()
          local api_t = {
            name = "example",
            upstream_url = "http://example.com",
            hosts = { "*.example.*" },
          }

          local ok, errors = validate_entity(api_t, api_schema)
          assert.is_false(ok)
          assert.matches("Only one wildcard is allowed", errors.hosts)
        end)
      end)
    end)

    describe("uris", function()
      it("accepts correct uris", function()
        local t = {
          name = "example",
          upstream_url = "http://example.org",
          uris = { "/path" },
        }

        local ok, errors = validate_entity(t, api_schema)
        assert.is_nil(errors)
        assert.is_true(ok)
      end)

      it("accepts unreserved characters from RFC 3986", function()
        local t = {
          name = "example",
          upstream_url = "http://example.org",
          uris = { "/abcd~user~2" },
        }

        local ok, errors = validate_entity(t, api_schema)
        assert.is_nil(errors)
        assert.is_true(ok)
      end)

      it("accepts reserved characters from RFC 3986 (considered as a regex)", function()
        local t = {
          name = "example",
          upstream_url = "http://example.org",
          uris = { "/users/[a-z]+/" },
        }

        local ok, errors = validate_entity(t, api_schema)
        assert.is_nil(errors)
        assert.is_true(ok)
      end)

      it("accepts properly %-encoded characters", function()
        local valids = {"/abcd%aa%10%ff%AA%FF"}

        for _, v in ipairs(valids) do
            local t = {
              name = "example",
              upstream_url = "http://example.com",
              uris = { v },
            }

            local ok, errors = validate_entity(t, api_schema)
            assert.is_nil(errors)
            assert.is_true(ok)
        end
      end)

      it("should not accept without prefix slash", function()
        local invalids = {"status", "status/123"}

        for _, v in ipairs(invalids) do
          local t = {
            name = "example",
            upstream_url = "http://example.com",
            uris = { v },
          }

          local ok, errors = validate_entity(t, api_schema)
          assert.is_false(ok)
          assert.equal("uri with value '" .. v .. "' is invalid: must be prefixed with slash", errors.uris)
        end
      end)

      it("accepts root (prefix slash)", function()
        local ok, errors = validate_entity({
          name = "example",
          upstream_url = "http://example.com",
          uris = { "/" },
        }, api_schema)

        assert.falsy(errors)
        assert.is_true(ok)
      end)

      it("removes trailing slashes", function()
        local valids = {"/status/", "/status/123/"}

        for _, v in ipairs(valids) do
          local t = {
            name = "example",
            upstream_url = "http://example.com",
            uris = { v },
          }

          local ok, errors = validate_entity(t, api_schema)
          assert.is_nil(errors)
          assert.is_true(ok)
          assert.matches(string.sub(v, 1, -2), t.uris[1], nil, true)
        end
      end)

      describe("errors", function()
        it("rejects values that are not strings", function()
          local t = {
            name = "example",
            upstream_url = "http://example.com",
            uris = { 123 },
          }

          local ok, errors = validate_entity(t, api_schema)
          assert.is_false(ok)
          assert.equal("uri with value '123' is invalid: must be a string", errors.uris)
        end)

        it("rejects empty strings", function()
          local invalids = { "", "   " }

          for _, v in ipairs(invalids) do
            local t = {
              name = "example",
              upstream_url = "http://example.com",
              uris = { v },
            }

            local ok, errors = validate_entity(t, api_schema)
            assert.is_false(ok)
            assert.matches("uri is empty", errors.uris, nil, true)
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
              name = "example",
              upstream_url = "http://example.com",
              uris = { v },
            }

            local ok, errors = validate_entity(t, api_schema)
            assert.is_false(ok)
            assert.matches("must use proper encoding; '" .. errstr[i] .. "' is invalid", errors.uris, nil, true)
          end
        end)

        it("rejects uris without prefix slash", function()
          local invalids = {"status", "status/123"}

          for _, v in ipairs(invalids) do
            local t = {
              name = "example",
              upstream_url = "http://example.com",
              uris = { v },
            }

            local ok, errors = validate_entity(t, api_schema)
            assert.is_false(ok)
            assert.matches("must be prefixed with slash", errors.uris, nil, true)
          end
        end)

        it("rejects invalid URIs", function()
          local invalids = {"//status", "/status//123", "/status/123//"}

          for _, v in ipairs(invalids) do
            local t = {
              name = "example",
              upstream_url = "http://example.com",
              uris = { v },
            }

            local ok, errors = validate_entity(t, api_schema)
            assert.is_false(ok)
            assert.matches("invalid", errors.uris, nil, true)
          end
        end)

        it("rejects regex URIs that are invalid regexes", function()
          local invalids = { [[/users/(foo/profile]] }

          for _, v in ipairs(invalids) do
            local t = {
              name = "example",
              upstream_url = "http://example.com",
              uris = { v },
            }

            local ok, errors = validate_entity(t, api_schema)
            assert.is_false(ok)
            assert.matches("invalid regex", errors.uris, nil, true)
          end
        end)
      end)
    end)

    describe("methods", function()
      it("accepts correct methods", function()
        local t = {
          name = "example",
          upstream_url = "http://example.org",
          methods = { "GET", "POST" },
        }

        local ok, errors = validate_entity(t, api_schema)
        assert.is_nil(errors)
        assert.is_true(ok)
      end)

      describe("errors", function()
        it("rejects values that are not strings", function()
          local t = {
            name = "example",
            upstream_url = "http://example.com",
            methods = { 123 },
          }

          local ok, errors = validate_entity(t, api_schema)
          assert.is_false(ok)
          assert.equal("method with value '123' is invalid: must be a string", errors.methods)
        end)

        it("rejects empty strings", function()
          local invalids = { "", "   " }

          for _, v in ipairs(invalids) do
            local t = {
              name = "example",
              upstream_url = "http://example.com",
              methods = { v },
            }

            local ok, errors = validate_entity(t, api_schema)
            assert.is_false(ok)
            assert.matches("method is empty", errors.methods, nil, true)
          end
        end)

        it("rejects invalid values", function()
          local invalids = { "HELLO WORLD", " GET", "get" }

          for _, v in ipairs(invalids) do
            local t = {
              name = "example",
              upstream_url = "http://example.com",
              methods = { v },
            }

            local ok, errors = validate_entity(t, api_schema)
            assert.is_false(ok)
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
            name = "example",
            upstream_url = "http://example.com",
            hosts = { "mydomain.com" },
            retries = v,
          }

          local valid, errors = validate_entity(t, api_schema)
          assert.falsy(errors)
          assert.is_true(valid)
        end
      end)
      it("rejects invalid values", function()
        local valids = { -5, 32768}
        for _, v in ipairs(valids) do
          local t = {
            name = "example",
            upstream_url = "http://example.com",
            hosts = { "mydomain.com" },
            retries = v,
          }

          local valid, errors = validate_entity(t, api_schema)
          assert.is_false(valid)
          assert.equal("must be an integer between 0 and 32767", errors.retries)
        end
      end)
    end)

    it("should complain if no [hosts] or [uris] or [methods]", function()
      local ok, errors, self_err = validate_entity({
        name = "example",
        upstream_url = "http://example.org",
      }, api_schema)

      assert.is_false(ok)
      assert.is_nil(errors)
      assert.equal("at least one of 'hosts', 'uris' or 'methods' must be specified", tostring(self_err))
    end)

    describe("timeouts", function()
      local fields = {
        "upstream_connect_timeout",
        "upstream_send_timeout",
        "upstream_read_timeout",
      }

      for i = 1, #fields do
        local field = fields[i]

        it(field .. " accepts valid values", function()
          local valids = { 1, 60000, 100000, 100 }

          for j = 1, #valids do
            assert(validate_entity({
              name         = "api",
              upstream_url = "http://example.org",
              methods      = "GET",
              [field]      = valids[j],
            }, api_schema))
          end
        end)

        it(field .. " refuses invalid values", function()
          local invalids = { -1, 0, 2^31, -100, 0.12 }

          for j = 1, #invalids do
            local ok, errors = validate_entity({
              name         = "api",
              upstream_url = "http://example.org",
              methods      = "GET",
              [field]      = invalids[j],
            }, api_schema)

            assert.is_false(ok)
            assert.equal("must be an integer between 1 and " .. 2^31 - 1, errors[field])
          end
        end)
      end
    end)
  end)

  --
  -- Consumer
  --

  describe("Consumers", function()
    it("should require a `custom_id` or `username`", function()
      local valid, errors = validate_entity({}, consumer_schema)
      assert.is_false(valid)
      assert.equal("At least a 'custom_id' or a 'username' must be specified", errors.username)
      assert.equal("At least a 'custom_id' or a 'username' must be specified", errors.custom_id)

      valid, errors = validate_entity({ username = "" }, consumer_schema)
      assert.is_false(valid)
      assert.equal("At least a 'custom_id' or a 'username' must be specified", errors.username)
      assert.equal("At least a 'custom_id' or a 'username' must be specified", errors.custom_id)

      valid, errors = validate_entity({ username = true }, consumer_schema)
      assert.is_false(valid)
      assert.equal("username is not a string", errors.username)
      assert.equal("At least a 'custom_id' or a 'username' must be specified", errors.custom_id)
    end)

    it("has a cache_key", function()
      assert.is_table(consumer_schema.cache_key)
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

    it("has a cache_key", function()
      assert.is_table(plugins_schema.cache_key)
    end)

    it("should not validate if the plugin doesn't exist (not installed)", function()
      local valid, errors = validate_entity({name = "world domination"}, plugins_schema)
      assert.is_false(valid)
      assert.equal("Plugin \"world domination\" not found", errors.config)
    end)
    it("should validate a plugin configuration's `config` field", function()
      -- Success
      local plugin = {name = "key-auth", api_id = "stub", config = {key_names = {"x-kong-key"}}}
      local valid = validate_entity(plugin, plugins_schema, {dao = dao_stub})
      assert.is_true(valid)

      -- Failure
      plugin = {name = "rate-limiting", api_id = "stub", config = { second = "hello" }}

      local valid, errors = validate_entity(plugin, plugins_schema, {dao = dao_stub})
      assert.is_false(valid)
      assert.equal("second is not a number", errors["config.second"])
    end)
    it("should have an empty config if none is specified and if the config schema does not have default", function()
      -- Insert key-auth, whose config has some default values that should be set
      local plugin = {name = "key-auth", api_id = "stub"}
      local valid = validate_entity(plugin, plugins_schema, {dao = dao_stub})
      assert.same({key_names = {"apikey"}, hide_credentials = false, anonymous = "", key_in_body = false}, plugin.config)
      assert.is_true(valid)
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
      assert.is_true(valid)
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
        assert.is_false(valid)
        assert.equal("No consumer can be configured for that plugin", err.message)

        valid, err = validate_entity({name = "stub", api_id = "0000", config = {string = "foo"}}, plugins_schema, {dao = dao_stub})
        assert.is_true(valid)
        assert.falsy(err)
      end)
    end)
  end)

  --
  -- UPSTREAMS
  --

  describe("Upstreams", function()
    local slots_default, slots_min, slots_max = 100, 10, 2^16

    it("should require a valid `name` and no port", function()
      local valid, errors, check
      valid, errors = validate_entity({}, upstreams_schema)
      assert.is_false(valid)
      assert.equal("name is required", errors.name)

      valid, errors, check = validate_entity({ name = "123.123.123.123" }, upstreams_schema)
      assert.is_false(valid)
      assert.is_nil(errors)
      assert.equal("Invalid name; no ip addresses allowed", check.message)

      valid, errors, check = validate_entity({ name = "\\\\bad\\\\////name////" }, upstreams_schema)
      assert.is_false(valid)
      assert.is_nil(errors)
      assert.equal("Invalid name; must be a valid hostname", check.message)

      valid, errors, check = validate_entity({ name = "name:80" }, upstreams_schema)
      assert.is_false(valid)
      assert.is_nil(errors)
      assert.equal("Invalid name; no port allowed", check.message)

      valid, errors, check = validate_entity({ name = "valid.host.name" }, upstreams_schema)
      assert.is_true(valid)
      assert.is_nil(errors)
      assert.is_nil(check)
    end)

    it("should require (optional) slots in a valid range", function()
      local valid, errors, check, _
      local data = { name = "valid.host.name" }
      valid, _, _ = validate_entity(data, upstreams_schema)
      assert.is_true(valid)
      assert.equal(slots_default, data.slots)

      local bad_slots = { -1, slots_min - 1, slots_max + 1 }
      for _, slots in ipairs(bad_slots) do
        local data = {
          name = "valid.host.name",
          slots = slots,
        }
        valid, errors, check = validate_entity(data, upstreams_schema)
        assert.is_false(valid)
        assert.is_nil(errors)
        assert.equal("number of slots must be between " .. slots_min .. " and " .. slots_max, check.message)
      end

      local good_slots = { slots_min, 500, slots_max }
      for _, slots in ipairs(good_slots) do
        local data = {
          name = "valid.host.name",
          slots = slots,
        }
        valid, errors, check = validate_entity(data, upstreams_schema)
        assert.is_true(valid)
        assert.is_nil(errors)
        assert.is_nil(check)
      end
    end)

    it("should require (optional) orderlist to be a proper list", function()
      local data, valid, errors, check
      local function validate_order(list, size)
        assert(type(list) == "table", "expected list table, got " .. type(list))
        assert(next(list), "table is empty")
        assert(type(size) == "number", "expected size number, got " .. type(size))
        assert(size > 0, "expected size to be > 0")
        local c = {}
        local max = 0
        for i,v in pairs(list) do  --> note: pairs, not ipairs!!
          if i > max then max = i end
          c[i] = v
        end
        assert(max == size, "highest key is not equal to the size")
        table.sort(c)
        max = 0
        for i, v in ipairs(c) do
          assert(i == v, "expected sorted table to have equal keys and values")
          if i>max then max = i end
        end
        assert(max == size, "expected array, but got list with holes")
      end

      for _ = 1, 20 do  -- have Kong generate 20 random sized arrays and verify them
        data = {
          name = "valid.host.name",
          slots = math.random(slots_min, slots_max)
        }
        valid, errors, check = validate_entity(data, upstreams_schema)
        assert.is_true(valid)
        assert.is_nil(errors)
        assert.is_nil(check)
        validate_order(data.orderlist, data.slots)
      end

      local lst = { 9,7,5,3,1,2,4,6,8,10 }   -- a valid list
      data = {
        name = "valid.host.name",
        slots = 10,
        orderlist = utils.shallow_copy(lst)
      }
      valid, errors, check = validate_entity(data, upstreams_schema)
      assert.is_true(valid)
      assert.is_nil(errors)
      assert.is_nil(check)
      assert.same(lst, data.orderlist)

      data = {
        name = "valid.host.name",
        slots = 10,
        orderlist = { 9,7,5,3,1,2,4,6,8 }   -- too short (9)
      }
      valid, errors, check = validate_entity(data, upstreams_schema)
      assert.is_false(valid)
      assert.is_nil(errors)
      assert.are.equal("size mismatch between 'slots' and 'orderlist'",check.message)

      data = {
        name = "valid.host.name",
        slots = 10,
        orderlist = { 9,7,5,3,1,2,4,6,8,10,11 }   -- too long (11)
      }
      valid, errors, check = validate_entity(data, upstreams_schema)
      assert.is_false(valid)
      assert.is_nil(errors)
      assert.are.equal("size mismatch between 'slots' and 'orderlist'",check.message)

      data = {
        name = "valid.host.name",
        slots = 10,
        orderlist = { 9,7,5,3,1,2,4,6,8,8 }   -- a double value (2x 8, no 10)
      }
      valid, errors, check = validate_entity(data, upstreams_schema)
      assert.is_false(valid)
      assert.is_nil(errors)
      assert.are.equal("invalid orderlist",check.message)

      data = {
        name = "valid.host.name",
        slots = 10,
        orderlist = { 9,7,5,3,1,2,4,6,8,11 }   -- a hole (10 missing)
      }
      valid, errors, check = validate_entity(data, upstreams_schema)
      assert.is_false(valid)
      assert.is_nil(errors)
      assert.are.equal("invalid orderlist",check.message)
    end)

  end)

  --
  -- TARGETS
  --

  describe("Targets", function()
    local weight_default, weight_min, weight_max = 100, 0, 1000
    local default_port = 8000

    it("should validate the required 'target' field", function()
      local valid, errors, check

      valid, errors, check = validate_entity({}, targets_schema)
      assert.is_false(valid)
      assert.equal(errors.target, "target is required")
      assert.is_nil(check)

      local names = { "valid.name", "valid.name:8080", "12.34.56.78", "1.2.3.4:123" }
      for _, name in ipairs(names) do
        valid, errors, check = validate_entity({ target = name }, targets_schema)
        assert.is_true(valid)
        assert.is_nil(errors)
        assert.is_nil(check)
      end

      valid, errors, check = validate_entity({ target = "\\\\bad\\\\////name////" }, targets_schema)
      assert.is_false(valid)
      assert.is_nil(errors)
      assert.equal("Invalid target; not a valid hostname or ip address", check.message)

    end)

    it("should normalize 'target' field and verify default port", function()
      local valid, errors, check

      -- the utils module does the normalization, here just check whether it is being invoked.
      local names_in = { "012.034.056.078", "01.02.03.04:123" }
      local names_out = { "12.34.56.78:" .. default_port, "1.2.3.4:123" }
      for i, name in ipairs(names_in) do
        local data = { target = name }
        valid, errors, check = validate_entity(data, targets_schema)
        assert.is_true(valid)
        assert.is_nil(errors)
        assert.is_nil(check)
        assert.equal(names_out[i], data.target)
      end
    end)

    it("should validate the optional 'weight' field", function()
      local weights, valid, errors, check

      weights = { -10, weight_min - 1, weight_max + 1 }
      for _, weight in ipairs(weights) do
        valid, errors, check = validate_entity({ target = "1.2.3.4", weight = weight }, targets_schema)
        assert.is_false(valid)
        assert.is_nil(errors)
        assert.equal("weight must be from " .. weight_min .. " to " .. weight_max, check.message)
      end

      weights = { weight_min, weight_default, weight_max }
      for _, weight in ipairs(weights) do
        valid, errors, check = validate_entity({ target = "1.2.3.4", weight = weight }, targets_schema)
        assert.is_true(valid)
        assert.is_nil(errors)
        assert.is_nil(check)
      end
    end)
  end)

  describe("update", function()
    it("should only validate updated fields", function()
      -- does not complain about the missing "name" field

      local t = {
        upstream_url = "http://example.com",
        hosts = { "" },
      }

      local ok, errors = validate_entity(t, api_schema, {
        update = true
      })

      assert.is_false(ok)
      assert.same({
        hosts = "host with value '' is invalid: host is empty"
      }, errors)
    end)
  end)
end)
