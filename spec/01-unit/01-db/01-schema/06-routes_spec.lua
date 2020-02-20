local routes = require "kong.db.schema.entities.routes"
local routes_subschemas = require "kong.db.schema.entities.routes_subschemas"
local services = require "kong.db.schema.entities.services"
local Schema = require "kong.db.schema"
local certificates = require "kong.db.schema.entities.certificates"
local Entity       = require "kong.db.schema.entity"

assert(Schema.new(certificates))
assert(Schema.new(services))
local Routes = assert(Entity.new(routes))

for name, subschema in pairs(routes_subschemas) do
  Routes:new_subschema(name, subschema)
end


describe("routes schema", function()
  local a_valid_uuid = "cbb297c0-a956-486d-ad1d-f9b42df9465a"
  local another_uuid = "64a8670b-900f-44e7-a900-6ec7ef5aa4d3"
  local uuid_pattern = "^" .. ("%x"):rep(8) .. "%-" .. ("%x"):rep(4) .. "%-"
                           .. ("%x"):rep(4) .. "%-" .. ("%x"):rep(4) .. "%-"
                           .. ("%x"):rep(12) .. "$"

  it("validates a valid route", function()
    local route = {
      id             = a_valid_uuid,
      name           = "my_route",
      protocols      = { "http" },
      methods        = { "GET", "POST" },
      hosts          = { "example.com" },
      headers        = { location = { "location-1" } },
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

  it("it does not fail when service is null", function()
    local route = { service = ngx.null, paths = {"/"} }
    route = Routes:process_auto_fields(route, "insert")
    local ok, errs = Routes:validate_insert(route)
    assert.truthy(ok)
    assert.is_nil(errs)
  end)

  it("it does not fail when service is missing", function()
    local route = { paths = {"/"} }
    route = Routes:process_auto_fields(route, "insert")
    local ok, errs = Routes:validate_insert(route)
    assert.truthy(ok)
    assert.is_nil(errs)
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

  it("missing method, host, headers, path & service produces error", function()
    local s = { id = "a4fbd24e-6a52-4937-bd78-2536713072d2" }
    local tests = {
      { 1,    { protocols = { "http" },                                }, {} },
      { true, { protocols = { "http" }, service = s, methods = {"GET"} }, {"hosts", "paths"} },
      { true, { protocols = { "http" }, service = s, hosts = {"x.y"} },   {"methods", "paths"} },
      { true, { protocols = { "http" }, service = s, paths = {"/foo"} },  {"methods", "hosts"} },
      { true, { protocols = { "http" }, service = s, headers = { location = { "location-1" } } }, {"methods", "hosts", "paths"} },
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

  it("conflicting protocols produces error", function()
    local protocols_tests = {
      { {"http", "tcp"}, "('http', 'https'), ('tcp', 'tls')" },
      { {"http", "tls"}, "('http', 'https'), ('tcp', 'tls')" },
      { {"https", "tcp"}, "('http', 'https'), ('tcp', 'tls')" },
      { {"https", "tls"}, "('http', 'https'), ('tcp', 'tls')" },
    }

    for _, test in ipairs(protocols_tests) do
      local route = Routes:process_auto_fields({ protocols = test[1] }, "insert")
      local ok, errs = Routes:validate(route)
      assert.falsy(ok)
      assert.truthy(errs["protocols"])
      assert.same(("these sets are mutually exclusive: %s"):format(test[2]), errs["protocols"])
    end
  end)

  it("invalid https_redirect_status_code produces error", function()

    local route = Routes:process_auto_fields({ protocols = { "http" },
                                               https_redirect_status_code = 404,
                                             }, "insert")
    local ok, errs = Routes:validate(route)
    assert.falsy(ok)
    assert.truthy(errs["https_redirect_status_code"])
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
    assert.same(ngx.null,      route.name)
    assert.same({ "http" },    route.protocols)
    assert.same(ngx.null,      route.methods)
    assert.same(ngx.null,      route.hosts)
    assert.same(ngx.null,      route.headers)
    assert.same({ "/foo" },    route.paths)
    assert.same(0,             route.regex_priority)
    assert.same(true,          route.strip_path)
    assert.same(false,         route.preserve_host)
    assert.same(426,           route.https_redirect_status_code)
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
        protocols = {"http"}
      }

      local ok, err = Routes:validate(route)
      assert.falsy(ok)
      assert.equal("expected a string", err.paths[1])
    end)

    it("must be a non-empty string", function()
      local route = {
        paths = { "" },
        protocols = { "http" },
      }

      local ok, err = Routes:validate(route)
      assert.falsy(ok)
      assert.equal("length must be at least 1", err.paths[1])
    end)

    it("must start with /", function()
      local route = {
        paths = { "foo" },
        protocols = { "http" },
      }

      local ok, err = Routes:validate(route)
      assert.falsy(ok)
      assert.equal("should start with: /", err.paths[1])
    end)

    it("must not have empty segments (/foo//bar)", function()
      local route = {
        paths = {
          "/foo//bar",
          "/foo/bar//",
          "//foo/bar",
        },
        protocols = { "http" },
      }

      local ok, err = Routes:validate(route)
      assert.falsy(ok)
      assert.equal("must not have empty segments", err.paths[1])
      assert.equal("must not have empty segments", err.paths[2])
      assert.equal("must not have empty segments", err.paths[3])
    end)

    it("must dry-run values that are considered regexes", function()
      local u = require("spec.helpers").unindent

      local invalid_paths = {
        [[/users/(foo/profile]],
      }

      for i = 1, #invalid_paths do
        local route = {
          paths = { invalid_paths[i] },
          protocols = { "http" },
        }

        local ok, err = Routes:validate(route)
        assert.falsy(ok)
        assert.equal(u([[invalid regex: '/users/(foo/profile' (PCRE returned:
                         pcre_compile() failed: missing ) in
                         "/users/(foo/profile")]], true, true), err.paths[1])
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
          protocols = { "http" },
        }

        local ok, err = Routes:validate(route)
        assert.falsy(ok)
        assert.matches("invalid url-encoded value: '" .. errstr[i] .. "'",
                       err.paths[1], nil, true)
      end
    end)

    -- acceptance
    it("accepts an apex '/'", function()
      local route = Routes:process_auto_fields({
        protocols = { "http" },
        service = { id = a_valid_uuid },
        methods = {},
        hosts = {},
        paths = { "/" },
      }, "insert")

      local ok, err = Routes:validate(route)
      assert.is_nil(err)
      assert.is_true(ok)
    end)

    it("accepts unreserved characters from RFC 3986", function()
      local route = Routes:process_auto_fields({
        protocols = { "http" },
        service = { id = a_valid_uuid },
        methods = {},
        hosts = {},
        paths = { "/abcd~user~2" },
      }, "insert")

      local ok, err = Routes:validate(route)
      assert.is_nil(err)
      assert.is_true(ok)
    end)

    it("accepts properly percent-encoded values", function()
      local valid_paths = { "/abcd%aa%10%ff%AA%FF" }

      for i = 1, #valid_paths do
        local route = Routes:process_auto_fields({
          protocols = { "http" },
          service = { id = a_valid_uuid },
          methods = {},
          hosts = {},
          paths = { valid_paths[i] },
        }, "insert")

        local ok, err = Routes:validate(route)
        assert.is_nil(err)
        assert.is_true(ok)
      end
    end)

    it("accepts trailing slash", function()
      local route = Routes:process_auto_fields({
        protocols = { "http" },
        service = { id = a_valid_uuid },
        methods = {},
        hosts = {},
        paths = { "/ovo/" },
      }, "insert")

      local ok, err = Routes:validate(route)
      assert.is_nil(err)
      assert.is_true(ok)
    end)
  end)

  describe("hosts attribute", function()
    -- refusals
    it("must be a string", function()
      local route = {
        hosts = { false },
        protocols = { "http" },
      }

      local ok, err = Routes:validate(route)
      assert.falsy(ok)
      assert.equal("expected a string", err.hosts[1])
    end)

    it("must be a non-empty string", function()
      local route = {
        hosts = { "" },
        protocols = { "http" },
      }

      local ok, err = Routes:validate(route)
      assert.falsy(ok)
      assert.equal("length must be at least 1", err.hosts[1])
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
          protocols = { "http" },
        }

        local ok, err = Routes:validate(route)
        assert.falsy(ok)
        assert.equal("invalid hostname: " .. invalid_hosts[i], err.hosts[1])
      end
    end)

    it("rejects values with an invalid port", function()
      local route = {
        hosts = { "example.com:1000000" },
        protocols = { "http" },
      }

      local ok, err = Routes:validate(route)
      assert.falsy(ok)
      assert.equal("invalid port number", err.hosts[1])
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
          protocols = { "http" },
        }

        local ok, err = Routes:validate(route)
        assert.falsy(ok)
        assert.equal("invalid wildcard: must be placed at leftmost or " ..
                     "rightmost label", err.hosts[1])
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
          protocols = { "http" },
        }

        local ok, err = Routes:validate(route)
        assert.falsy(ok)
        assert.equal("invalid wildcard: must have at most one wildcard",
                     err.hosts[1])
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
        "example.com:80",
        "example.com:8080",
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
        local route = Routes:process_auto_fields({
          protocols = { "http" },
          service = { id = a_valid_uuid },
          methods = {},
          paths = {},
          hosts = { valid_hosts[i] },
        }, "insert")

        local ok, err = Routes:validate(route)
        assert.is_nil(err)
        assert.is_true(ok)
      end
    end)

    it("accepts hosts with valid wildcard", function()
      local valid_hosts = {
        "example.*",
        "*.example.org",
        "*.example.org:321",
      }

      for i = 1, #valid_hosts do
        local route = Routes:process_auto_fields({
          protocols = { "http" },
          service = { id = a_valid_uuid },
          methods = {},
          paths = {},
          hosts = { valid_hosts[i] },
        }, "insert")

        local ok, err = Routes:validate(route)
        assert.is_nil(err)
        assert.is_true(ok)
      end
    end)
  end)

  describe("headers attribute", function()
    -- refusals
    it("key must be a string", function()
      local route = {
        headers = { false },
        protocols = { "http" },
      }

      local ok, err = Routes:validate(route)
      assert.falsy(ok)
      assert.equal("expected a string", err.headers)
    end)

    it("cannot contain 'host' key", function()
      local values = { "host", "Host", "HoSt" }

      for _, v in ipairs(values) do
        local route = {
          headers = { [v] = { "example.com" } },
          protocols = { "http" },
        }

        local ok, err = Routes:validate(route)
        assert.falsy(ok)
        assert.equal("cannot contain 'host' header, which must be specified " ..
                     "in the 'hosts' attribute", err.headers)
      end
    end)

    it("value must be an array", function()
      local route = {
        headers = { location = true },
        protocols = { "http" },
      }

      local ok, err = Routes:validate(route)
      assert.falsy(ok)
      assert.equal("expected an array", err.headers)
    end)

    it("values must be a string", function()
      local route = {
        headers = { location = { true } },
        protocols = { "http" },
      }

      local ok, err = Routes:validate(route)
      assert.falsy(ok)
      assert.equal("expected a string", err.headers[1])
    end)

    it("values must be non-empty string", function()
      local route = {
        headers = { location = { "" } },
        protocols = { "http" },
      }

      local ok, err = Routes:validate(route)
      assert.falsy(ok)
      assert.equal("length must be at least 1", err.headers[1])
    end)
  end)

  describe("methods attribute", function()
    -- refusals
    it("must be a string", function()
      local route = {
        methods = { false },
        protocols = { "http" },
      }

      local ok, err = Routes:validate(route)
      assert.falsy(ok)
      assert.equal("expected a string", err.methods[1])
    end)

    it("must be a non-empty string", function()
      local route = {
        methods = { "" },
        protocols = { "http" },
      }

      local ok, err = Routes:validate(route)
      assert.falsy(ok)
      assert.equal("length must be at least 1", err.methods[1])
    end)

    it("rejects invalid values", function()
      local invalid_methods = {
        "HELLO WORLD",
        " GET",
      }

      for i = 1, #invalid_methods do
        local route = {
          methods = { invalid_methods[i] },
          protocols = { "http" },
        }

        local ok, err = Routes:validate(route)
        assert.falsy(ok)
        assert.equal("invalid value: " .. invalid_methods[i],
                     err.methods[1])
      end
    end)

    it("rejects non-uppercased values", function()
      local route = {
        methods = { "get" },
        protocols = { "http" },
      }

      local ok, err = Routes:validate(route)
      assert.falsy(ok)
      assert.equal("invalid value: get", err.methods[1])
    end)

    -- acceptance
    it("accepts valid HTTP methods", function()
      local valid_methods = {
        "GET",
        "POST",
        "CUSTOM",
      }

      for i = 1, #valid_methods do
        local route = Routes:process_auto_fields({
          protocols = { "http" },
          service = { id = a_valid_uuid },
          paths = {},
          hosts = {},
          methods = { valid_methods[i] },
        }, "insert")

        local ok, err = Routes:validate(route)
        assert.is_nil(err)
        assert.is_true(ok)
      end
    end)
  end)

  describe("name attribute", function()
    -- refusals
    it("must be a string", function()
      local route = {
        name = false,
        protocols = {"http"}
      }

      local ok, err = Routes:validate(route)
      assert.falsy(ok)
      assert.equal("expected a string", err.name)
    end)

    it("must be a non-empty string", function()
      local route = {
        name = "",
        protocols = {"http"}
      }

      local ok, err = Routes:validate(route)
      assert.falsy(ok)
      assert.equal("length must be at least 1", err.name)
    end)

    it("rejects invalid names", function()
      local invalid_names = {
        "examp:le",
        "examp;le",
        "examp/le",
        "examp le",
      }

      for i = 1, #invalid_names do
        local route = {
          name = invalid_names[i],
          protocols = {"http"}
        }

        local ok, err = Routes:validate(route)
        assert.falsy(ok)
        assert.equal(
          "invalid value '" .. invalid_names[i] .. "': it must only contain alphanumeric and '., -, _, ~' characters",
          err.name)
      end
    end)

    -- acceptance
    it("accepts valid names", function()
      local valid_names = {
        "example",
        "EXAMPLE",
        "exa.mp.le",
        "3x4mp13",
        "3x4-mp-13",
        "3x4_mp_13",
        "~3x4~mp~13",
        "~3..x4~.M-p~1__3_",
      }

      for i = 1, #valid_names do
        local route = Routes:process_auto_fields({
          protocols = { "http" },
          paths = { "/" },
          name = valid_names[i],
          service = { id = a_valid_uuid }
        }, "insert")

        local ok, err = Routes:validate(route)
        assert.is_nil(err)
        assert.is_true(ok)
      end
    end)
  end)

  describe("#stream context", function()
    it("'protocol' accepts 'tcp'", function()
      local s = { id = "a4fbd24e-6a52-4937-bd78-2536713072d2" }

      local route = Routes:process_auto_fields({
        protocols = { "tcp" },
        sources = {{ ip = "127.0.0.1" }},
        service = s,
      }, "insert")
      local ok, errs = Routes:validate(route)
      assert.is_nil(errs)
      assert.truthy(ok)
      assert.same({ "tcp" }, route.protocols)
    end)

    it("'protocol' accepts 'tls'", function()
      local s = { id = "a4fbd24e-6a52-4937-bd78-2536713072d2" }
      local route = Routes:process_auto_fields({
        protocols = { "tls" },
        sources = {{ ip = "127.0.0.1" }},
        service = s,
      }, "insert")
      local ok, errs = Routes:validate(route)
      assert.is_nil(errs)
      assert.truthy(ok)
      assert.same({ "tls" }, route.protocols)
    end)

    it("if 'protocol = tcp/tls', then 'paths' is empty", function()
      local s = { id = "a4fbd24e-6a52-4937-bd78-2536713072d2" }
      for _, v in ipairs({ "tcp", "tls" }) do
        local route = Routes:process_auto_fields({
          protocols = { v },
          sources = {{ ip = "127.0.0.1" }},
          paths = { "/" },
          service = s,
        }, "insert")
        local ok, errs = Routes:validate(route)
        assert.falsy(ok)
        assert.same({
          paths = "cannot set 'paths' when 'protocols' is 'tcp' or 'tls'",
        }, errs)
      end
    end)

    it("if 'protocol = tcp/tls', then 'methods' is empty", function()
      local s = { id = "a4fbd24e-6a52-4937-bd78-2536713072d2" }
      for _, v in ipairs({ "tcp", "tls" }) do
        local route = Routes:process_auto_fields({
          protocols = { v },
          sources = {{ ip = "127.0.0.1" }},
          methods = { "GET" },
          service = s,
        }, "insert")
        local ok, errs = Routes:validate(route)
        assert.falsy(ok)
        assert.same({
          methods = "cannot set 'methods' when 'protocols' is 'tcp' or 'tls'",
        }, errs)
      end
    end)

    describe("'sources' and 'destinations' matching attributes", function()
      local s = { id = "a4fbd24e-6a52-4937-bd78-2536713072d2" }
      for _, v in ipairs({
        "sources",
        "destinations"
      }) do
        it("'" .. v .. "' accepts valid IPs and ports", function()
          for _, protocol in ipairs({ "tcp", "tls" }) do
            local route = Routes:process_auto_fields({
              protocols = { protocol },
              [v] = {
                { ip = "127.75.78.72", port = 8000 },
              },
              service = s,
            }, "insert")
            local ok, errs = Routes:validate(route)
            assert.is_nil(errs)
            assert.truthy(ok)
            assert.same({ protocol }, route.protocols)
            assert.same({ ip = "127.75.78.72", port = 8000 }, route[v][1])
          end
        end)

        it("'" .. v .. "' accepts valid IPs (no port)", function()
          for _, protocol in ipairs({ "tcp", "tls" }) do
            local route = Routes:process_auto_fields({
              protocols = { protocol },
              [v] = {
                { ip = "127.0.0.1" },
                { ip = "127.75.78.72", port = 8000 },
              },
              service = s,
            }, "insert")
            local ok, errs = Routes:validate(route)
            assert.is_nil(errs)
            assert.truthy(ok)
            assert.same({ protocol }, route.protocols)
            assert.same({ ip = "127.0.0.1", port = ngx.null }, route[v][1])
          end
        end)

        it("'" .. v .. "' accepts valid ports (no IP)", function()
          for _, protocol in ipairs({ "tcp", "tls" }) do
            local route = Routes:process_auto_fields({
              protocols = { protocol },
              [v] = {
                { port = 8000 },
                { ip = "127.75.78.72", port = 8000 },
              },
              service = s,
            }, "insert")
            local ok, errs = Routes:validate(route)
            assert.is_nil(errs)
            assert.truthy(ok)
            assert.same({ protocol }, route.protocols)
            assert.same({ ip = ngx.null, port = 8000 }, route[v][1])
          end
        end)

        it("'" .. v .. "' rejects invalid 'port' values", function()
          for _, protocol in ipairs({ "tcp", "tls" }) do
            local route = Routes:process_auto_fields({
              protocols = { protocol },
              [v] = {
                { ip = "127.0.0.1" },
                { ip = "127.75.78.72", port = 65536 },
              },
              service = s,
            }, "insert")
            local ok, errs = Routes:validate(route)
            assert.falsy(ok)
            assert.same({
              [v] = { [2] = { port = "value should be between 0 and 65535" } },
            }, errs)
          end
        end)

        it("'" .. v .. "' rejects invalid 'ip' values", function()
          -- invalid IPs
          for _, ip_val in ipairs({ "127.", ":::1", "-1", "localhost", "foo" }) do
            for _, protocol in ipairs({ "tcp", "tls" }) do
              local route = Routes:process_auto_fields({
                protocols = { protocol },
                [v] = {
                  { ip = ip_val },
                  { ip = "127.75.78.72", port = 8000 },
                },
                service = s,
              }, "insert")
              local ok, errs = Routes:validate(route)
              assert.falsy(ok, "ip test value was valid: " .. ip_val)
              assert.equal("invalid ip or cidr range: '" .. ip_val .. "'", errs[v][1].ip)
            end
          end

          -- hostnames
          for _, ip_val in ipairs({ "f", "example.org" }) do
            for _, protocol in ipairs({ "tcp", "tls" }) do
              local route = Routes:process_auto_fields({
                protocols = { protocol },
                [v] = {
                  { ip = ip_val },
                  { ip = "127.75.78.72", port = 8000 },
                },
                service = s,
              }, "insert")
              local ok, errs = Routes:validate(route)
              assert.falsy(ok, "ip test value was valid: " .. ip_val)
              assert.equal("invalid ip or cidr range: '" .. ip_val .. "'", errs[v][1].ip)
            end
          end
        end)

        it("'" .. v .. "' accepts valid 'ip cidr' values", function()
          -- valid CIDRs
          for _, ip_val in ipairs({ "1/0", "2130706433/2", "4294967295/3",
                                    "0.0.0.0/0", "::/0", "0.0.0.0/1", "::/1",
                                    "0.0.0.0/32", "::/128" }) do
            for _, protocol in ipairs({ "tcp", "tls" }) do
              local route = Routes:process_auto_fields({
                protocols = { protocol },
                [v] = {
                  { ip = ip_val },
                  { ip = "127.75.78.72", port = 8000 },
                },
                service = s,
              }, "insert")
              local ok, errs = Routes:validate(route)
              assert.truthy(ok, "ip test value was valid: " .. ip_val)
              assert.is_nil(errs)
            end
          end
        end)

        it("'" .. v .. "' rejects invalid 'ip cidr' values", function()
          -- invalid CIDRs
          for _, ip_val in ipairs({ "-1/0", "4294967296/2", "0.0.0.0/a",
                                    "::/a", "0.0.0.0/-1", "::/-1",
                                    "0.0.0.0/33", "::/129" }) do
            for _, protocol in ipairs({ "tcp", "tls" }) do
              local route = Routes:process_auto_fields({
                protocols = { protocol },
                [v] = {
                  { ip = ip_val },
                  { ip = "127.75.78.72", port = 8000 },
                },
                service = s,
              }, "insert")
              local ok, errs = Routes:validate(route)
              assert.falsy(ok, "ip test value was valid: " .. ip_val)
              assert.equal("invalid ip or cidr range: '" .. ip_val .. "'", errs[v][1].ip)
            end
          end
        end)
      end
    end)

    describe("'snis' matching attribute", function()
      local s = { id = "a4fbd24e-6a52-4937-bd78-2536713072d2" }

      for _, protocol in ipairs { "tls", "https", "grpcs" } do
        it("accepts valid SNIs for " .. protocol .. " Routes", function()
          for _, sni in ipairs({ "example.org", "www.example.org" }) do
            local route = Routes:process_auto_fields({
              protocols = { protocol },
              snis = { sni },
              service = s,
            }, "insert")
            local ok, errs = Routes:validate(route)
            assert.is_nil(errs)
            assert.truthy(ok)
          end
        end)
      end

      it("rejects invalid SNIs", function()
        for _, sni in ipairs({ "127.0.0.1", "example.org:80" }) do
          local route = Routes:process_auto_fields({
            protocols = { "tcp", "tls" },
            snis = { sni },
            service = s,
          }, "insert")
          local ok, errs = Routes:validate(route)
          assert.falsy(ok, "sni test value was valid: " .. sni)
          if not pcall(function()
                         assert.matches("must not be an IP", errs.snis[1], nil,
                                        true)
                       end)
          then
            assert.matches("must not have a port", errs.snis[1], nil, true)
          end
        end
      end)

      it("rejects specifying 'snis' if 'protocols' does not have 'https' or 'tls'", function()
        local route = Routes:process_auto_fields({
          protocols = { "tcp" },
          snis = { "example.org" },
          service = s,
        }, "insert")
        local ok, errs = Routes:validate(route)
        assert.falsy(ok)
        assert.same({
          ["@entity"] = {
            "'snis' can only be set when 'protocols' is 'grpcs', 'https' or 'tls'",
          },
          snis = "length must be 0",
        }, errs)
      end)
    end)

    it("errors if no L4 matching attribute set", function()
      local s = { id = "a4fbd24e-6a52-4937-bd78-2536713072d2" }
      for _, v in ipairs({ "tcp", "tls" }) do
        local route = Routes:process_auto_fields({
          protocols = { v },
          service = s,
        }, "insert")
        local ok, errs = Routes:validate(route)
        assert.falsy(ok)
        assert.same({
          ["@entity"] = {
            "must set one of 'sources', 'destinations', 'snis' when 'protocols' is 'tcp' or 'tls'"
          }
        }, errs)
      end
    end)
  end)

  it("errors if no L7 matching attribute set", function()
    local s = { id = "a4fbd24e-6a52-4937-bd78-2536713072d2" }
    local route = Routes:process_auto_fields({
      protocols = { "http" },
      service = s,
    }, "insert")
    local ok, errs = Routes:validate(route)
    assert.falsy(ok)
    assert.same({
      ["@entity"] = {
        "must set one of 'methods', 'hosts', 'headers', 'paths' when 'protocols' is 'http'"
      }
    }, errs)

    route = Routes:process_auto_fields({
      protocols = { "https" },
      service = s,
    }, "insert")
    ok, errs = Routes:validate(route)
    assert.falsy(ok)
    assert.same({
      ["@entity"] = {
        "must set one of 'methods', 'hosts', 'headers', 'paths', 'snis' when 'protocols' is 'https'"
      }
    }, errs)
  end)

  it("errors if no L7 matching attribute set", function()
    local s = { id = "a4fbd24e-6a52-4937-bd78-2536713072d2" }
    local route = Routes:process_auto_fields({
      protocols = { "grpc" },
      service = s,
    }, "insert")
    local ok, errs = Routes:validate(route)
    assert.falsy(ok)
    assert.same({
      ["@entity"] = {
        "must set one of 'hosts', 'headers', 'paths' when 'protocols' is 'grpc'"
      }
    }, errs)

    route = Routes:process_auto_fields({
      protocols = { "grpcs" },
      service = s,
    }, "insert")
    ok, errs = Routes:validate(route)
    assert.falsy(ok)
    assert.same({
      ["@entity"] = {
        "must set one of 'hosts', 'headers', 'paths', 'snis' when 'protocols' is 'grpcs'"
      }
    }, errs)
  end)

  it("errors if methods attribute is set on grpc/grpcs", function()
    local s = { id = "a4fbd24e-6a52-4937-bd78-2536713072d2" }
    local route = Routes:process_auto_fields({
      methods = "GET",
      paths = { "/foo" },
      protocols = { "grpc" },
      service = s,
    }, "insert")
    local ok, errs = Routes:validate(route)
    assert.falsy(ok)
    assert.same({
      methods = "cannot set 'methods' when 'protocols' is 'grpc' or 'grpcs'"
    }, errs)

    route = Routes:process_auto_fields({
      methods = "GET",
      paths = { "/foo" },
      protocols = { "grpcs" },
      service = s,
    }, "insert")
    ok, errs = Routes:validate(route)
    assert.falsy(ok)
    assert.same({
      methods = "cannot set 'methods' when 'protocols' is 'grpc' or 'grpcs'"
    }, errs)
  end)

  it("errors if methods attribute is set on grpc/grpcs", function()
    local s = { id = "a4fbd24e-6a52-4937-bd78-2536713072d2" }
    local route = Routes:process_auto_fields({
      methods = "GET",
      paths = { "/foo" },
      protocols = { "grpc" },
      service = s,
    }, "insert")
    local ok, errs = Routes:validate(route)
    assert.falsy(ok)
    assert.same({
      methods = "cannot set 'methods' when 'protocols' is 'grpc' or 'grpcs'"
    }, errs)

    route = Routes:process_auto_fields({
      methods = "GET",
      paths = { "/foo" },
      protocols = { "grpcs" },
      service = s,
    }, "insert")
    ok, errs = Routes:validate(route)
    assert.falsy(ok)
    assert.same({
      methods = "cannot set 'methods' when 'protocols' is 'grpc' or 'grpcs'"
    }, errs)
  end)

  it("errors if strip_path is set on grpc/grpcs", function()
    local s = { id = "a4fbd24e-6a52-4937-bd78-2536713072d2" }
    local route = Routes:process_auto_fields({
      hosts = { "foo.grpc.com" },
      protocols = { "grpc" },
      strip_path = true,
      service = s,
    }, "insert")
    local ok, errs = Routes:validate(route)
    assert.falsy(ok)
    assert.same({
      strip_path = "cannot set 'strip_path' when 'protocols' is 'grpc' or 'grpcs'"
    }, errs)

    route = Routes:process_auto_fields({
      hosts = { "foo.grpc.com" },
      protocols = { "grpcs" },
      strip_path = true,
      service = s,
    }, "insert")
    ok, errs = Routes:validate(route)
    assert.falsy(ok)
    assert.same({
      strip_path = "cannot set 'strip_path' when 'protocols' is 'grpc' or 'grpcs'"
    }, errs)
  end)
end)
