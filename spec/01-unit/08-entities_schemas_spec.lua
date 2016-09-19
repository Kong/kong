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
        local invalids = {"/mockbin", ".mockbin", "mockbin.", "mock;bin",
                          "mockbin.com/org",
                          "mockbin-.org", "mockbin.org-",
                          "hello..mockbin.com", "hello-.mockbin.com"}

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
                        "hello.abcd", "mockbin_api.com", "localhost",
                        -- punycode examples from RFC3492; https://tools.ietf.org/html/rfc3492#page-14
                        -- specifically the japanese ones as they mix ascii with escaped characters
                        "3B-ww4c5e180e575a65lsy2b", "-with-SUPER-MONKEYS-pc58ag80a8qai00g7n9n",
                        "Hello-Another-Way--fc4qua05auwb3674vfr0b", "2-u9tlzr9756bt3uc0v",
                        "MajiKoi5-783gue6qz075azm5e", "de-jg4avhby1noc0d", "d9juau41awczczp",
                        }

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
      it("should refuse invalid wildcard request_host placement", function()
        local invalids = {"*mockbin.com", "www.mockbin*", "mock*bin.com"}

        for _, v in ipairs(invalids) do
          local t = {request_host = v, upstream_url = "http://mockbin.com", name = "mockbin"}
          local valid, errors = validate_entity(t, api_schema)
          assert.equal("Invalid wildcard placement: "..v, (errors and errors.request_host or ""))
          assert.False(valid)
        end
      end)
      it("should refuse invalid wildcard request_host", function()
        local invalids = {"/mockbin", ".mockbin", "mockbin.", "mock;bin",
                          "mockbin.com/org",
                          "mockbin-.org", "mockbin.org-",
                          "hello..mockbin.com", "hello-.mockbin.com"}

        for _, v in ipairs(invalids) do
          v = "*."..v 
          local t = {request_host = v, upstream_url = "http://mockbin.com", name = "mockbin"}
          local valid, errors = validate_entity(t, api_schema)
          assert.equal("Invalid value: "..v, (errors and errors.request_host or ""))
          assert.falsy(errors.request_path)
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
          assert.equal("must only contain alphanumeric and '., -, _, ~, /, %' characters", errors.request_path)
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
      it("should not accept bad %-encoded characters", function()
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
          local t = {request_path = v, upstream_url = "http://mockbin.com", name = "mockbin"}
          local valid, errors = validate_entity(t, api_schema)
          assert.False(valid)
          assert.equal("must use proper encoding; '"..errstr[i].."' is invalid", errors.request_path)
        end
      end)
      it("should accept properly %-encoded characters", function()
        local valids = {"/abcd%aa%10%ff%AA%FF"}
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
  
    describe("retries", function()
      it("accepts valid values", function()
        local valids = {0, 5, 100, 32767}
        for _, v in ipairs(valids) do
          local t = {request_host = "mydomain.com", upstream_url = "http://mockbin.com", name = "mockbin", retries = v}
          local valid, errors = validate_entity(t, api_schema)
          assert.falsy(errors)
          assert.True(valid)
        end
      end)
      it("rejects invalid values", function()
        local valids = { -5, 32768}
        for _, v in ipairs(valids) do
          local t = {request_host = "mydomain.com", upstream_url = "http://mockbin.com", name = "mockbin", retries = v}
          local valid, errors = validate_entity(t, api_schema)
          assert.False(valid)
          assert.equal("retries must be a integer, from 0 to 32767", errors.retries)
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

  --
  -- UPSTREAMS
  --

  describe("Upstreams", function()
    local slots_default, slots_min, slots_max = 100, 10, 2^16

    it("should require a valid `name` and no port", function()
      local valid, errors, check
      valid, errors = validate_entity({}, upstreams_schema)
      assert.False(valid)
      assert.equal("name is required", errors.name)

      valid, errors, check = validate_entity({ name = "123.123.123.123" }, upstreams_schema)
      assert.False(valid)
      assert.Nil(errors)
      assert.equal("Invalid name; no ip addresses allowed", check.message)

      valid, errors, check = validate_entity({ name = "\\\\bad\\\\////name////" }, upstreams_schema)
      assert.False(valid)
      assert.Nil(errors)
      assert.equal("Invalid name; must be a valid hostname", check.message)
      
      valid, errors, check = validate_entity({ name = "name:80" }, upstreams_schema)
      assert.False(valid)
      assert.Nil(errors)
      assert.equal("Invalid name; no port allowed", check.message)
      
      valid, errors, check = validate_entity({ name = "valid.host.name" }, upstreams_schema)
      assert.True(valid)
      assert.Nil(errors)
      assert.Nil(check)
    end)

    it("should require (optional) slots in a valid range", function()
      local valid, errors, check
      local data = { name = "valid.host.name" }
      valid, errors, check = validate_entity(data, upstreams_schema)
      assert.True(valid)
      assert.equal(slots_default, data.slots)

      local bad_slots = { -1, slots_min - 1, slots_max + 1 }
      for _, slots in ipairs(bad_slots) do
        local data = { 
          name = "valid.host.name",
          slots = slots,
        }
        valid, errors, check = validate_entity(data, upstreams_schema)
        assert.False(valid)
        assert.Nil(errors)
        assert.equal("number of slots must be between "..slots_min.." and "..slots_max, check.message)
      end
      
      local good_slots = { slots_min, 500, slots_max }
      for _, slots in ipairs(good_slots) do
        local data = { 
          name = "valid.host.name",
          slots = slots,
        }
        valid, errors, check = validate_entity(data, upstreams_schema)
        assert.True(valid)
        assert.Nil(errors)
        assert.Nil(check)
      end
    end)
  
    it("should require (optional) orderlist to be a proper list", function()
      local data, valid, errors, check
      local function validate_order(list, size)
        assert(type(list) == "table", "expected list table, got "..type(list))
        assert(next(list), "table is empty")
        assert(type(size) == "number", "expected size number, got "..type(size))
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
        assert.True(valid)
        assert.Nil(errors)
        assert.Nil(check)
        validate_order(data.orderlist, data.slots)
      end

      local lst = { 9,7,5,3,1,2,4,6,8,10 }   -- a valid list
      data = { 
        name = "valid.host.name",
        slots = 10,
        orderlist = utils.shallow_copy(lst)
      }
      valid, errors, check = validate_entity(data, upstreams_schema)
      assert.True(valid)
      assert.Nil(errors)
      assert.Nil(check)
      assert.same(lst, data.orderlist)
    
      data = { 
        name = "valid.host.name",
        slots = 10,
        orderlist = { 9,7,5,3,1,2,4,6,8 }   -- too short (9)
      }
      valid, errors, check = validate_entity(data, upstreams_schema)
      assert.False(valid)
      assert.Nil(errors)
      assert.are.equal("size mismatch between 'slots' and 'orderlist'",check.message)

      data = { 
        name = "valid.host.name",
        slots = 10,
        orderlist = { 9,7,5,3,1,2,4,6,8,10,11 }   -- too long (11)
      }
      valid, errors, check = validate_entity(data, upstreams_schema)
      assert.False(valid)
      assert.Nil(errors)
      assert.are.equal("size mismatch between 'slots' and 'orderlist'",check.message)

      data = { 
        name = "valid.host.name",
        slots = 10,
        orderlist = { 9,7,5,3,1,2,4,6,8,8 }   -- a double value (2x 8, no 10)
      }
      valid, errors, check = validate_entity(data, upstreams_schema)
      assert.False(valid)
      assert.Nil(errors)
      assert.are.equal("invalid orderlist",check.message)

      data = { 
        name = "valid.host.name",
        slots = 10,
        orderlist = { 9,7,5,3,1,2,4,6,8,11 }   -- a hole (10 missing)
      }
      valid, errors, check = validate_entity(data, upstreams_schema)
      assert.False(valid)
      assert.Nil(errors)
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
      assert.False(valid)
      assert.equal(errors.target, "target is required")
      assert.is_nil(check)

      local names = { "valid.name", "valid.name:8080", "12.34.56.78", "1.2.3.4:123" }
      for _, name in ipairs(names) do
        valid, errors, check = validate_entity({ target = name }, targets_schema)
        assert.True(valid)
        assert.is_nil(errors)
        assert.is_nil(check)
      end

      valid, errors, check = validate_entity({ target = "\\\\bad\\\\////name////" }, targets_schema)
      assert.False(valid)
      assert.Nil(errors)
      assert.equal("Invalid target; not a valid hostname or ip address", check.message)

    end)
    
    it("should normalize 'target' field and verify default port", function()
      local valid, errors, check

      -- the utils module does the normalization, here just check whether it is being invoked.
      local names_in = { "012.034.056.078", "01.02.03.04:123" }
      local names_out = { "12.34.56.78:"..default_port, "1.2.3.4:123" }
      for i, name in ipairs(names_in) do
        local data = { target = name }
        valid, errors, check = validate_entity(data, targets_schema)
        assert.True(valid)
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
        assert.False(valid)
        assert.is_nil(errors)
        assert.equal("weight must be from "..weight_min.." to "..weight_max, check.message)
      end

      weights = { weight_min, weight_default, weight_max }
      for _, weight in ipairs(weights) do
        valid, errors, check = validate_entity({ target = "1.2.3.4", weight = weight }, targets_schema)
        assert.True(valid)
        assert.is_nil(errors)
        assert.is_nil(check)
      end
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
