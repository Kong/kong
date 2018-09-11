local api_schema = require "kong.dao.schemas.apis"
local validations = require "kong.dao.schemas_validation"
local validate_entity = validations.validate_entity

describe("Entities Schemas", function()

  for k, schema in pairs({api = api_schema}) do
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
end)
