local routes = require "kong.db.schema.entities.routes"
local Schema = require "kong.db.schema"


local Routes = Schema.new(routes)


describe("routes schema", function()
  local a_valid_uuid = "cbb297c0-a956-486d-ad1d-f9b42df9465a"
  local another_uuid = "64a8670b-900f-44e7-a900-6ec7ef5aa4d3"
  local uuid_pattern = "^" .. ("%x"):rep(8) .. "%-" .. ("%x"):rep(4) .. "%-"
                           .. ("%x"):rep(4) .. "%-" .. ("%x"):rep(4) .. "%-"
                           .. ("%x"):rep(12) .. "$"

  it("validates a valid route", function()
    local route = {
      id             = a_valid_uuid,
      protocols      = { "http" },
      methods        = { "GET", "POST" },
      hosts          = { "example.com" },
      paths          = { "/ovo" },
      regex_priority = 1,
      strip_path     = false,
      preserve_host  = true,
      service        = { id = another_uuid },
    }
    route = Routes:process_auto_fields(route, "insert")
    assert.truthy(route.created_at)
    assert.truthy(route.updated_at)
    assert.same(route.created_at, route.updated_at)
    assert.truthy(Routes:validate(route))
    assert.falsy(route.strip_path)
  end)

  it("fails when service is null", function()
    local route = { service = ngx.null, paths = {"/"} }
    route = Routes:process_auto_fields(route, "insert")
    local ok, errs = Routes:validate_insert(route)
    assert.falsy(ok)
    assert.truthy(errs["service"])
  end)

  it("fails when service.id is null", function()
    local route = { service = { id = ngx.null }, paths = {"/"} }
    route = Routes:process_auto_fields(route, "insert")
    local ok, errs = Routes:validate_insert(route)
    assert.falsy(ok)
    assert.truthy(errs["service"])
  end)

  it("fails when protocol is missing", function()
    local route = { protocols = ngx.null }
    route = Routes:process_auto_fields(route, "insert")
    local ok, errs = Routes:validate_insert(route)
    assert.falsy(ok)
    assert.truthy(errs["protocols"])
  end)

  it("fails given an invalid method", function()
    local route = {
      protocols = { "http" },
      methods = { "get" },
    }
    route = Routes:process_auto_fields(route, "insert")
    local ok, errs = Routes:validate(route)
    assert.falsy(ok)
    assert.truthy(errs["methods"])
  end)

  it("missing method, host, path & service produces error", function()
    local s = { id = "a4fbd24e-6a52-4937-bd78-2536713072d2" }
    local tests = {
      { 1,    { protocols = { "http" },                                }, {} },
      { true, { protocols = { "http" }, service = s, methods = {"GET"} }, {"hosts", "paths"} },
      { true, { protocols = { "http" }, service = s, hosts = {"x.y"} },   {"methods", "paths"} },
      { true, { protocols = { "http" }, service = s, paths = {"/foo"} },     {"methods", "hosts"} },
    }
    for i, test in ipairs(tests) do
      test[2] = Routes:process_auto_fields(test[2], "insert")
      local ok, errs = Routes:validate(test[2])
      if test[1] == true then
        assert.truthy(ok, "case " .. tostring(i) .. " failed")
        assert.falsy(errs)
      else
        assert.falsy(ok)
        for _, name in ipairs(test[3]) do
          assert.truthy(errs[name], "case " .. tostring(i) .. " failed: " .. name)
        end
      end
    end
  end)

  it("invalid protocols produces error", function()

    local route = Routes:process_auto_fields({ protocols = {} }, "insert")
    local ok, errs = Routes:validate(route)
    assert.falsy(ok)
    assert.truthy(errs["protocols"])

    local route2 = Routes:process_auto_fields({ protocols = { "ftp" } }, "insert")
    local ok, errs = Routes:validate(route2)
    assert.falsy(ok)
    assert.truthy(errs["protocols"])
  end)

  it("produces defaults", function()
    local route = {
      protocols = { "http" },
      service = { id = "5abfe322-9fc1-4e0e-bfa3-007f5b9ac4b4" },
      paths = { "/foo" }
    }
    route = Routes:process_auto_fields(route, "insert")
    local ok, err = Routes:validate(route)
    assert.is_nil(err)
    assert.truthy(ok)
    assert.match(uuid_pattern, route.id)
    assert.same({ "http" },    route.protocols)
    assert.same(ngx.null,      route.methods)
    assert.same(ngx.null,      route.hosts)
    assert.same({ "/foo" },    route.paths)
    assert.same(0,             route.regex_priority)
    assert.same(true,          route.strip_path)
    assert.same(false,         route.preserve_host)
  end)

  it("validates the foreign key in entities", function()
    local route = {
      protocols = { "http" },
      paths = { "/foo" },
      service = {
        id = "blergh",
      }
    }
    route = Routes:process_auto_fields(route, "insert")
    local ok, errs = Routes:validate(route)
    assert.falsy(ok)
    assert.truthy(errs["service"])
    assert.truthy(errs["service"]["id"])
  end)

  it("gives access to foreign schemas", function()
    assert.truthy(Routes.fields.service)
    assert.truthy(Routes.fields.service.schema)
    assert.truthy(Routes.fields.service.schema.fields)
  end)

  describe("paths attribute", function()
    -- refusals
    it("must be a string", function()
      local route = {
        paths = { false },
      }

      local ok, err = Routes:validate(route)
      assert.falsy(ok)
      assert.equal("expected a string", err.paths)
    end)

    it("must be a non-empty string", function()
      local route = {
        paths = { "" },
      }

      local ok, err = Routes:validate(route)
      assert.falsy(ok)
      assert.equal("length must be at least 1", err.paths)
    end)

    it("must start with /", function()
      local route = {
        paths = { "foo" },
      }

      local ok, err = Routes:validate(route)
      assert.falsy(ok)
      assert.equal("should start with: /", err.paths)
    end)

    it("must not have empty segments (/foo//bar)", function()
      local invalid_paths = {
        "/foo//bar",
        "/foo/bar//",
        "//foo/bar",
      }

      for i = 1, #invalid_paths do
        local route = {
          paths = { invalid_paths[i] },
        }

        local ok, err = Routes:validate(route)
        assert.falsy(ok)
        assert.equal("must not have empty segments", err.paths)
      end
    end)

    it("must dry-run values that are considered regexes", function()
      local u = require("spec.helpers").unindent

      local invalid_paths = {
        [[/users/(foo/profile]],
      }

      for i = 1, #invalid_paths do
        local route = {
          paths = { invalid_paths[i] },
        }

        local ok, err = Routes:validate(route)
        assert.falsy(ok)
        assert.equal(u([[invalid regex: '/users/(foo/profile' (PCRE returned:
                         pcre_compile() failed: missing ) in
                         "/users/(foo/profile")]], true, true), err.paths)
      end
    end)

    it("rejects badly percent-encoded values", function()
      local invalid_paths = {
        "/some%2words",
        "/some%0Xwords",
        "/some%2Gwords",
        "/some%20words%",
        "/some%20words%a",
        "/some%20words%ax",
      }

      local errstr = { "%2w", "%0X", "%2G", "%", "%a", "%ax" }

      for i = 1, #invalid_paths do
        local route = {
          paths = { invalid_paths[i] },
        }

        local ok, err = Routes:validate(route)
        assert.falsy(ok)
        assert.matches("invalid url-encoded value: '" .. errstr[i] .. "'",
                       err.paths, nil, true)
      end
    end)

    -- acceptance
    it("accepts an apex '/'", function()
      local route = {
        protocols = { "http" },
        service = { id = a_valid_uuid },
        methods = {},
        hosts = {},
        paths = { "/" },
      }

      local ok, err = Routes:validate(route)
      assert.is_nil(err)
      assert.is_true(ok)
    end)

    it("accepts unreserved characters from RFC 3986", function()
      local route = {
        protocols = { "http" },
        service = { id = a_valid_uuid },
        methods = {},
        hosts = {},
        paths = { "/abcd~user~2" },
      }

      local ok, err = Routes:validate(route)
      assert.is_nil(err)
      assert.is_true(ok)
    end)

    it("accepts properly percent-encoded values", function()
      local valid_paths = { "/abcd%aa%10%ff%AA%FF" }

      for i = 1, #valid_paths do
        local route = {
          protocols = { "http" },
          service = { id = a_valid_uuid },
          methods = {},
          hosts = {},
          paths = { valid_paths[i] },
        }

        local ok, err = Routes:validate(route)
        assert.is_nil(err)
        assert.is_true(ok)
      end
    end)

    it("rejects trailing slash", function()
      local route = {
        protocols = { "http" },
        service = { id = a_valid_uuid },
        methods = {},
        hosts = {},
        paths = { "/ovo/" },
      }

      local ok, err = Routes:validate(route)
      assert.falsy(ok)
      assert.match("must not have a trailing slash", err.paths)
    end)
  end)

  describe("hosts attribute", function()
    -- refusals
    it("must be a string", function()
      local route = {
        hosts = { false },
      }

      local ok, err = Routes:validate(route)
      assert.falsy(ok)
      assert.equal("expected a string", err.hosts)
    end)

    it("must be a non-empty string", function()
      local route = {
        hosts = { "" },
      }

      local ok, err = Routes:validate(route)
      assert.falsy(ok)
      assert.equal("length must be at least 1", err.hosts)
    end)

    it("rejects invalid hostnames", function()
      local invalid_hosts = {
        "/example",
        ".example",
        "example.",
        "example:",
        "mock;bin",
        "example.com/org",
        "example-.org",
        "example.org-",
        "hello..example.com",
        "hello-.example.com",
      }

      for i = 1, #invalid_hosts do
        local route = {
          hosts = { invalid_hosts[i] },
        }

        local ok, err = Routes:validate(route)
        assert.falsy(ok)
        assert.equal("invalid value: " .. invalid_hosts[i], err.hosts)
      end
    end)

    it("rejects values with a valid port", function()
      local route = {
        hosts = { "example.com:80" }
      }

      local ok, err = Routes:validate(route)
      assert.falsy(ok)
      assert.equal("must not have a port", err.hosts)
    end)

    it("rejects values with an invalid port", function()
      local route = {
        hosts = { "example.com:1000000" }
      }

      local ok, err = Routes:validate(route)
      assert.falsy(ok)
      assert.equal("must not have a port", err.hosts)
    end)

    it("rejects invalid wildcard placement", function()
      local invalid_hosts = {
        "*example.com",
        "www.example*",
        "mock*bin.com",
      }

      for i = 1, #invalid_hosts do
        local route = {
          hosts = { invalid_hosts[i] },
        }

        local ok, err = Routes:validate(route)
        assert.falsy(ok)
        assert.equal("invalid wildcard: must be placed at leftmost or " ..
                     "rightmost label", err.hosts)
      end
    end)

    it("rejects host with too many wildcards", function()
      local invalid_hosts = {
        "*.example.*",
        "**.example.com",
        "*.example*.*",
      }

      for i = 1, #invalid_hosts do
        local route = {
          hosts = { invalid_hosts[i] },
        }

        local ok, err = Routes:validate(route)
        assert.falsy(ok)
        assert.equal("invalid wildcard: must have at most one wildcard",
                     err.hosts)
      end
    end)

    -- acceptance
    it("accepts valid hosts", function()
      local valid_hosts = {
        "hello.com",
        "hello.fr",
        "test.hello.com",
        "1991.io",
        "hello.COM",
        "HELLO.com",
        "123helloWORLD.com",
        "example.123",
        "example-api.com",
        "hello.abcd",
        "example_api.com",
        "localhost",
        -- below:
        -- punycode examples from RFC3492;
        -- https://tools.ietf.org/html/rfc3492#page-14
        -- specifically the japanese ones as they mix
        -- ascii with escaped characters
        "3B-ww4c5e180e575a65lsy2b",
        "-with-SUPER-MONKEYS-pc58ag80a8qai00g7n9n",
        "Hello-Another-Way--fc4qua05auwb3674vfr0b",
        "2-u9tlzr9756bt3uc0v",
        "MajiKoi5-783gue6qz075azm5e",
        "de-jg4avhby1noc0d",
        "d9juau41awczczp",
      }

      for i = 1, #valid_hosts do
        local route = {
          protocols = { "http" },
          service = { id = a_valid_uuid },
          methods = {},
          paths = {},
          hosts = { valid_hosts[i] },
        }

        local ok, err = Routes:validate(route)
        assert.is_nil(err)
        assert.is_true(ok)
      end
    end)

    it("accepts hosts with valid wildcard", function()
      local valid_hosts = {
        "example.*",
        "*.example.org",
      }

      for i = 1, #valid_hosts do
        local route = {
          protocols = { "http" },
          service = { id = a_valid_uuid },
          methods = {},
          paths = {},
          hosts = { valid_hosts[i] },
        }

        local ok, err = Routes:validate(route)
        assert.is_nil(err)
        assert.is_true(ok)
      end
    end)
  end)

  describe("methods attribute", function()
    -- refusals
    it("must be a string", function()
      local route = {
        methods = { false },
      }

      local ok, err = Routes:validate(route)
      assert.falsy(ok)
      assert.equal("expected a string", err.methods)
    end)

    it("must be a non-empty string", function()
      local route = {
        methods = { "" },
      }

      local ok, err = Routes:validate(route)
      assert.falsy(ok)
      assert.equal("length must be at least 1", err.methods)
    end)

    it("rejects invalid values", function()
      local invalid_methods = {
        "HELLO WORLD",
        " GET",
      }

      for i = 1, #invalid_methods do
        local route = {
          methods = { invalid_methods[i] },
        }

        local ok, err = Routes:validate(route)
        assert.falsy(ok)
        assert.equal("invalid value: " .. invalid_methods[i],
                     err.methods)
      end
    end)

    it("rejects non-uppercased values", function()
      local route = {
        methods = { "get" },
      }

      local ok, err = Routes:validate(route)
      assert.falsy(ok)
      assert.equal("invalid value: get", err.methods)
    end)

    -- acceptance
    it("accepts valid HTTP methods", function()
      local valid_methods = {
        "GET",
        "POST",
        "CUSTOM",
      }

      for i = 1, #valid_methods do
        local route = {
          protocols = { "http" },
          service = { id = a_valid_uuid },
          paths = {},
          hosts = {},
          methods = { valid_methods[i] },
        }

        local ok, err = Routes:validate(route)
        assert.is_nil(err)
        assert.is_true(ok)
      end
    end)
  end)
end)
