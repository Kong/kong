local services = require "kong.db.schema.entities.services"
local Schema = require "kong.db.schema"
local certificates = require "kong.db.schema.entities.certificates"
local Entity       = require "kong.db.schema.entity"

local Routes

local function setup_global_env()
  _G.kong = _G.kong or {}
  _G.kong.log = _G.kong.log or {
    debug = function(msg)
      ngx.log(ngx.DEBUG, msg)
    end,
    error = function(msg)
      ngx.log(ngx.ERR, msg)
    end,
    warn = function (msg)
      ngx.log(ngx.WARN, msg)
    end
  }
end

local function reload_flavor(flavor)
  _G.kong = {
    configuration = {
      router_flavor = flavor,
    },
  }

  package.loaded["kong.db.schema.entities.routes"] = nil
  package.loaded["kong.db.schema.entities.routes_subschemas"] = nil

  local routes = require "kong.db.schema.entities.routes"
  local routes_subschemas = require "kong.db.schema.entities.routes_subschemas"

  assert(Schema.new(certificates))
  assert(Schema.new(services))
  Routes = assert(Entity.new(routes))

  for name, subschema in pairs(routes_subschemas) do
    Routes:new_subschema(name, subschema)
  end
end


for _, flavor in ipairs({ "traditional", "traditional_compatible", "expressions" }) do
describe("routes schema (flavor = " .. flavor .. ")", function()
  local a_valid_uuid = "cbb297c0-a956-486d-ad1d-f9b42df9465a"
  local another_uuid = "64a8670b-900f-44e7-a900-6ec7ef5aa4d3"
  local uuid_pattern = "^" .. ("%x"):rep(8) .. "%-" .. ("%x"):rep(4) .. "%-"
                           .. ("%x"):rep(4) .. "%-" .. ("%x"):rep(4) .. "%-"
                           .. ("%x"):rep(12) .. "$"

  local it_trad_only = (flavor == "traditional") and it or pending

  reload_flavor(flavor)
  setup_global_env()

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
      { {"http", "tcp"}, "('http', 'https'), ('tcp', 'tls', 'udp')" },
      { {"http", "tls"}, "('http', 'https'), ('tcp', 'tls', 'udp')" },
      { {"https", "tcp"}, "('http', 'https'), ('tcp', 'tls', 'udp')" },
      { {"https", "tls"}, "('http', 'https'), ('tcp', 'tls', 'udp')" },
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
      assert.equal("should start with: / (fixed path) or ~/ (regex path)", err.paths[1])
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
        [[~/users/(foo/profile]],
      }

      for i = 1, #invalid_paths do
        local route = {
          paths = { invalid_paths[i] },
          protocols = { "http" },
        }

        local ok, err = Routes:validate(route)
        assert.falsy(ok)
        assert.equal(u([[invalid regex: '/users/(foo/profile' (PCRE returned:
                         pcre2_compile() failed: missing closing parenthesis in
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

    -- TODO: bump atc-router to fix it
    it_trad_only("accepts properly percent-encoded values", function()
      local valid_paths = { "/abcd\xaa\x10\xff\xAA\xFF" }

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
        -- see tests for utils.validate_utf8 for more invalid values
        string.char(105, 213, 205, 149),
      }

      for i = 1, #invalid_names do
        local route = {
          name = invalid_names[i],
          protocols = {"http"}
        }
        local ok, err = Routes:validate(route)
        assert.falsy(ok)
        assert.matches("invalid", err.name)
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
        "孔",
        "Конг",
        "🦍",
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

    it("'protocol' accepts 'udp'", function()
      local s = { id = "a4fbd24e-6a52-4937-bd78-2536713072d2" }
      local route = Routes:process_auto_fields({
        protocols = { "udp" },
        sources = {{ ip = "127.0.0.1" }},
        service = s,
      }, "insert")
      local ok, errs = Routes:validate(route)
      assert.is_nil(errs)
      assert.truthy(ok)
      assert.same({ "udp" }, route.protocols)
    end)

    it("if 'protocol = tcp/tls/udp', then 'paths' is empty", function()
      local s = { id = "a4fbd24e-6a52-4937-bd78-2536713072d2" }
      for _, v in ipairs({ "tcp", "tls", "udp" }) do
        local route = Routes:process_auto_fields({
          protocols = { v },
          sources = {{ ip = "127.0.0.1" }},
          paths = { "/" },
          service = s,
        }, "insert")
        local ok, errs = Routes:validate(route)
        assert.falsy(ok)
        assert.same({
          paths = "cannot set 'paths' when 'protocols' is 'tcp', 'tls', 'tls_passthrough' or 'udp'",
        }, errs)
      end
    end)

    it("if 'protocol = tcp/tls/udp', then 'methods' is empty", function()
      local s = { id = "a4fbd24e-6a52-4937-bd78-2536713072d2" }
      for _, v in ipairs({ "tcp", "tls", "udp" }) do
        local route = Routes:process_auto_fields({
          protocols = { v },
          sources = {{ ip = "127.0.0.1" }},
          methods = { "GET" },
          service = s,
        }, "insert")
        local ok, errs = Routes:validate(route)
        assert.falsy(ok)
        assert.same({
          methods = "cannot set 'methods' when 'protocols' is 'tcp', 'tls', 'tls_passthrough' or 'udp'",
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
          for _, protocol in ipairs({ "tcp", "tls", "udp" }) do
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
          for _, protocol in ipairs({ "tcp", "tls", "udp" }) do
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
          for _, protocol in ipairs({ "tcp", "tls", "udp" }) do
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
          for _, protocol in ipairs({ "tcp", "tls", "udp" }) do
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
            for _, protocol in ipairs({ "tcp", "tls", "udp" }) do
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
            for _, protocol in ipairs({ "tcp", "tls", "udp" }) do
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
          for _, ip_val in ipairs({ "0.0.0.0/0", "::/0", "0.0.0.0/1", "::/1",
                                    "0.0.0.0/32", "::/128" }) do
            for _, protocol in ipairs({ "tcp", "tls", "udp" }) do
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
          for _, ip_val in ipairs({ "1/0", "2130706433/2", "4294967295/3",
                                    "-1/0", "4294967296/2", "0.0.0.0/a",
                                    "::/a", "0.0.0.0/-1", "::/-1",
                                    "0.0.0.0/33", "::/129" }) do
            for _, protocol in ipairs({ "tcp", "tls", "udp" }) do
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

      it("rejects specifying 'snis' if 'protocols' does not have 'https', 'tls' or 'tls_passthrough'", function()
        local route = Routes:process_auto_fields({
          protocols = { "tcp", "udp" },
          snis = { "example.org" },
          service = s,
        }, "insert")
        local ok, errs = Routes:validate(route)
        assert.falsy(ok)
        assert.same({
          ["@entity"] = {
            "'snis' can only be set when 'protocols' is 'grpcs', 'https', 'tls' or 'tls_passthrough'",
          },
          snis = "length must be 0",
        }, errs)
      end)
    end)

    it("errors if no L4 matching attribute set", function()
      local s = { id = "a4fbd24e-6a52-4937-bd78-2536713072d2" }
      for _, v in ipairs({ "tcp", "tls", "udp" }) do
        local route = Routes:process_auto_fields({
          protocols = { v },
          service = s,
        }, "insert")
        local ok, errs = Routes:validate(route)
        assert.falsy(ok)
        assert.same({
          ["@entity"] = {
            "must set one of 'sources', 'destinations', 'snis'" ..
            (flavor == "expressions" and ", 'expression'" or "") .. " when 'protocols' is 'tcp', 'tls' or 'udp'"
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
        "must set one of 'methods', 'hosts', 'headers', 'paths'" ..
        (flavor == "expressions" and ", 'expression'" or "") .. " when 'protocols' is 'http'"
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
        "must set one of 'methods', 'hosts', 'headers', 'paths', 'snis'" ..
        (flavor == "expressions" and ", 'expression'" or "") .. " when 'protocols' is 'https'"
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
        "must set one of 'hosts', 'headers', 'paths'" ..
        (flavor == "expressions" and ", 'expression'" or "") .." when 'protocols' is 'grpc'"
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
        "must set one of 'hosts', 'headers', 'paths', 'snis'" ..
        (flavor == "expressions" and ", 'expression'" or "") .. " when 'protocols' is 'grpcs'"
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
      hosts = { "foo.grpc.test" },
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
      hosts = { "foo.grpc.test" },
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

  it("errors if tls and tls_passthrough set on a same route", function()
    local s = { id = "a4fbd24e-6a52-4937-bd78-2536713072d2" }
    local route = Routes:process_auto_fields({
      snis = { "foo.grpc.test" },
      protocols = { "tls", "tls_passthrough" },
      service = s,
    }, "insert")
    local ok, errs = Routes:validate(route)
    assert.falsy(ok)
    assert.same({
      protocols = "these sets are mutually exclusive: ('tcp', 'tls', 'udp'), ('tls_passthrough')",
    }, errs)
  end)

  it("errors if snis is not set on tls_passthrough", function()
    local s = { id = "a4fbd24e-6a52-4937-bd78-2536713072d2" }
    local route = Routes:process_auto_fields({
      sources = {{ ip = "127.0.0.1" }},
      protocols = { "tls_passthrough" },
      service = s,
    }, "insert")
    local ok, errs = Routes:validate(route)
    assert.falsy(ok)
    assert.same({
      ["@entity"] =  { "must set snis when 'protocols' is 'tls_passthrough'" },
    }, errs)
  end)

  it("errors for not-normalized prefix path", function ()
    local test_paths = {
      ["/%c3%A4"] = "/ä",
      ["/%20"] = "/ ",
      ["/%25"] = false,
    }
    for path, result in ipairs(test_paths) do
      local route = {
        paths = { path },
        protocols = { "http" },
      }

      local ok, err = Routes:validate(route)
      if not result then
        assert(ok)

      else
        assert.falsy(ok == result)
        assert.equal([[schema violation (paths.1: not normalized path. Suggest: ']] .. result .. [[')]], err.paths[1])
      end
    end

  end)
end)
end   -- for flavor


describe("routes schema (flavor = expressions)", function()
  local a_valid_uuid = "cbb297c0-a956-486d-ad1d-f9b42df9465a"
  local another_uuid = "64a8670b-900f-44e7-a900-6ec7ef5aa4d3"

  reload_flavor("expressions")
  setup_global_env()

  it("validates a valid route with only expression field", function()
    local route = {
      id             = a_valid_uuid,
      name           = "my_route",
      protocols      = { "http" },
      expression     = [[(http.method == "GET")]],
      priority       = 100,
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

  it("validates a valid route without expression field", function()
    local route = {
      id             = a_valid_uuid,
      name           = "my_route",
      protocols      = { "https" },

      methods        = { "GET", "POST" },
      hosts          = { "example.com" },
      headers        = { location = { "location-1" } },
      paths          = { "/ovo" },

      snis           = { "example.org" },
      sources        = {{ ip = "127.0.0.1" }},
      destinations   = {{ ip = "127.0.0.1" }},

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

  it("fails when set 'expression' and others simultaneously", function()
    local route = {
      id             = a_valid_uuid,
      name           = "my_route",
      protocols      = { "http" },
      expression     = [[(http.method == "GET")]],
      service        = { id = another_uuid },
    }

    local others = {
      methods        = { "GET", "POST" },
      hosts          = { "example.com" },
      headers        = { location = { "location-1" } },
      paths          = { "/ovo" },

      snis           = { "example.org" },
      sources        = {{ ip = "127.0.0.1" }},
      destinations   = {{ ip = "127.0.0.1" }},

      regex_priority = 100,
    }

    for k, v in pairs(others) do
      route[k] = v

      local r = Routes:process_auto_fields(route, "insert")
      local ok, errs = Routes:validate_insert(r)
      assert.falsy(ok)
      assert.truthy(errs["@entity"])

      route[k] = nil
    end
  end)

  it("fails when set 'priority' and others simultaneously", function()
    local route = {
      id             = a_valid_uuid,
      name           = "my_route",
      protocols      = { "http" },
      priority       = 100,
      service        = { id = another_uuid },
    }

    local others = {
      methods        = { "GET", "POST" },
      hosts          = { "example.com" },
      headers        = { location = { "location-1" } },
      paths          = { "/ovo" },

      snis           = { "example.org" },
      sources        = {{ ip = "127.0.0.1" }},
      destinations   = {{ ip = "127.0.0.1" }},
    }

    for k, v in pairs(others) do
      route[k] = v

      local r = Routes:process_auto_fields(route, "insert")
      local ok, errs = Routes:validate_insert(r)
      assert.falsy(ok)
      assert.truthy(errs["@entity"])

      route[k] = nil
    end
  end)

  it("fails when priority is missing", function()
    local route = { priority = ngx.null }
    route = Routes:process_auto_fields(route, "insert")
    local ok, errs = Routes:validate_insert(route)
    assert.falsy(ok)
    assert.truthy(errs["priority"])
  end)

  it("fails when priority is more than 2^46 - 1", function()
    local route = { priority = 2^46 }
    route = Routes:process_auto_fields(route, "insert")
    local ok, errs = Routes:validate_insert(route)
    assert.falsy(ok)
    assert.truthy(errs["priority"])
  end)

  it("fails when all fields is missing", function()
    local route = { expression = ngx.null }
    route = Routes:process_auto_fields(route, "insert")
    local ok, errs = Routes:validate_insert(route)
    assert.falsy(ok)
    assert.truthy(errs["@entity"])
  end)

  it("fails given an invalid expression", function()
    local route = {
      protocols  = { "http" },
      priority   = 100,
      expression = [[(http.method == "GET") &&]],
    }
    route = Routes:process_auto_fields(route, "insert")
    local ok, errs = Routes:validate(route)
    assert.falsy(ok)
    assert.truthy(errs["@entity"])
  end)
end)


for _, flavor in ipairs({ "traditional_compatible", "expressions" }) do
describe("routes schema (flavor = " .. flavor .. ")", function()
  local a_valid_uuid = "cbb297c0-a956-486d-ad1d-f9b42df9465a"
  local another_uuid = "64a8670b-900f-44e7-a900-6ec7ef5aa4d3"

  reload_flavor(flavor)
  setup_global_env()

  it("validates a valid http route", function()
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

  it("validates a valid stream route", function()
    local route = {
      id             = a_valid_uuid,
      name           = "my_route",
      protocols      = { "tcp" },
      sources        = { { ip = "1.2.3.4", port = 80 } },
      service        = { id = another_uuid },
    }
    route = Routes:process_auto_fields(route, "insert")
    assert.truthy(route.created_at)
    assert.truthy(route.updated_at)
    assert.same(route.created_at, route.updated_at)
    assert.truthy(Routes:validate(route))
  end)

  it("fails when path is invalid", function()
    local route = {
      id             = a_valid_uuid,
      name           = "my_route",
      protocols      = { "http" },
      paths          = { "~/[abc/*/user$" },
      service        = { id = another_uuid },
    }
    route = Routes:process_auto_fields(route, "insert")
    local ok, errs = Routes:validate_insert(route)
    assert.falsy(ok)
    assert.truthy(errs["paths"])
    assert.matches("invalid regex:", errs["paths"][1],
                   nil, true)

    -- verified by `schema/typedefs.lua`
    assert.falsy(errs["@entity"])
  end)

  it("fails when ip address is invalid", function()
    local route = {
      id             = a_valid_uuid,
      name           = "my_route",
      protocols      = { "tcp" },
      sources        = { { ip = "x.x.x.x", port = 80 } },
      service        = { id = another_uuid },
    }
    route = Routes:process_auto_fields(route, "insert")
    local ok, errs = Routes:validate_insert(route)
    assert.falsy(ok)
    assert.truthy(errs["sources"])

    -- verified by `schema/typedefs.lua`
    assert.falsy(errs["@entity"])
  end)

  it("won't fail when rust.regex update to 1.8", function()
    local route = {
      id             = a_valid_uuid,
      name           = "my_route",
      protocols      = { "http" },
      paths          = { "~/\\/*/user$" },
      service        = { id = another_uuid },
    }
    route = Routes:process_auto_fields(route, "insert")
    local ok, errs = Routes:validate_insert(route)
    assert.truthy(ok)
    assert.is_nil(errs)
  end)

  describe("'snis' matching attribute (wildcard)", function()
    local s = { id = "a4fbd24e-6a52-4937-bd78-2536713072d2" }

    it("accepts leftmost wildcard", function()
      for _, sni in ipairs({ "*.example.org", "*.foo.bar.test" }) do
        local route = Routes:process_auto_fields({
          protocols = { "https" },
          snis = { sni },
          service = s,
        }, "insert")
        local ok, errs = Routes:validate(route)
        assert.is_nil(errs)
        assert.truthy(ok)
      end
    end)

    it("accepts rightmost wildcard", function()
      for _, sni in ipairs({ "example.*", "foo.bar.*" }) do
        local route = Routes:process_auto_fields({
          protocols = { "https" },
          snis = { sni },
          service = s,
        }, "insert")
        local ok, errs = Routes:validate(route)
        assert.is_nil(errs)
        assert.truthy(ok)
      end
    end)

    it("rejects invalid wildcard", function()
      for _, sni in ipairs({ "foo.*.test", "foo*.test" }) do
        local route = Routes:process_auto_fields({
          protocols = { "https" },
          snis = { sni },
          service = s,
        }, "insert")
        local ok, errs = Routes:validate(route)
        assert.falsy(ok)
        assert.same({
          snis = {
            "wildcard must be leftmost or rightmost character",
          },
        }, errs)
      end
    end)
  end)
end)
end   -- flavor in ipairs({ "traditional_compatible", "expressions" })


describe("routes schema (flavor = expressions)", function()
  local a_valid_uuid = "cbb297c0-a956-486d-ad1d-f9b42df9465a"
  local another_uuid = "64a8670b-900f-44e7-a900-6ec7ef5aa4d3"

  reload_flavor("expressions")
  setup_global_env()

  it("validates a 'not' expression", function()
    local route = {
      id             = a_valid_uuid,
      name           = "my_route",
      protocols      = { "http" },
      expression     = [[!(http.method == "GET") && !(http.host == "example.com") && !(http.path ^= "/foo")]],
      priority       = 100,
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

  it("validates a valid http route", function()
    local route = {
      id             = a_valid_uuid,
      name           = "my_route",
      protocols      = { "http" },
      expression     = [[http.method == "GET" && http.host == "example.com" && http.path == "/ovo"]],
      priority       = 100,
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

  it("validates a valid stream route", function()
    local route = {
      id             = a_valid_uuid,
      name           = "my_route",
      protocols      = { "tcp" },
      expression     = [[net.src.ip == 1.2.3.4 && net.src.port == 80]],
      priority       = 100,
      service        = { id = another_uuid },
    }
    route = Routes:process_auto_fields(route, "insert")
    assert.truthy(route.created_at)
    assert.truthy(route.updated_at)
    assert.same(route.created_at, route.updated_at)
    assert.truthy(Routes:validate(route))
  end)

  it("fails when path is invalid", function()
    local route = {
      id             = a_valid_uuid,
      name           = "my_route",
      protocols      = { "http" },
      expression     = [[http.method == "GET" && http.path ~ "/[abc/*/user$"]],
      priority       = 100,
      service        = { id = another_uuid },
    }
    route = Routes:process_auto_fields(route, "insert")
    local ok, errs = Routes:validate_insert(route)
    assert.falsy(ok)

    assert.truthy(errs["@entity"])
  end)

  it("fails when ip address is invalid", function()
    local route = {
      id             = a_valid_uuid,
      name           = "my_route",
      protocols      = { "tcp" },
      expression     = [[net.src.ip in 1.2.3.4/16 && net.src.port == 80]],
      priority       = 100,
      service        = { id = another_uuid },
    }
    route = Routes:process_auto_fields(route, "insert")
    local ok, errs = Routes:validate_insert(route)
    assert.falsy(ok)

    assert.truthy(errs["@entity"])
  end)

  it("fails if http route's field appears in stream route", function()
    local route = {
      id             = a_valid_uuid,
      name           = "my_route",
      protocols      = { "tcp" },
      expression     = [[http.method == "GET" && net.src.ip == 1.2.3.4 && net.src.port == 80]],
      priority       = 100,
      service        = { id = another_uuid },
    }
    route = Routes:process_auto_fields(route, "insert")
    local ok, errs = Routes:validate_insert(route)
    assert.falsy(ok)

    assert.truthy(errs["@entity"])
  end)

  it("http route still supports net.port but with warning", function()
    local ngx_log = ngx.log
    local log = spy.on(ngx, "log")

    finally(function()
      ngx.log = ngx_log  -- luacheck: ignore
    end)

    local route = {
      id             = a_valid_uuid,
      name           = "my_route",
      protocols      = { "grpc" },
      expression     = [[http.method == "GET" && net.port == 8000]],
      priority       = 100,
      service        = { id = another_uuid },
    }
    route = Routes:process_auto_fields(route, "insert")
    assert.truthy(Routes:validate(route))

    assert.spy(log).was.called_with(ngx.WARN,
                                    "The field 'net.port' of expression is deprecated " ..
                                    "and will be removed in the upcoming major release, " ..
                                    "please use 'net.dst.port' instead.")
  end)

  it("http route supports net.src.* fields", function()
    local route = {
      id             = a_valid_uuid,
      name           = "my_route",
      protocols      = { "https" },
      expression     = [[http.method == "GET" && net.src.ip == 1.2.3.4 && net.src.port == 80]],
      priority       = 100,
      service        = { id = another_uuid },
    }
    route = Routes:process_auto_fields(route, "insert")
    assert.truthy(Routes:validate(route))
  end)

  it("http route supports net.dst.* fields", function()
    local route = {
      id             = a_valid_uuid,
      name           = "my_route",
      protocols      = { "grpcs" },
      expression     = [[http.method == "GET" && net.dst.ip == 1.2.3.4 && net.dst.port == 80]],
      priority       = 100,
      service        = { id = another_uuid },
    }
    route = Routes:process_auto_fields(route, "insert")
    assert.truthy(Routes:validate(route))
  end)

  it("http route supports http.path.segments.* fields", function()
    local r = {
      id             = a_valid_uuid,
      name           = "my_route",
      protocols      = { "grpcs" },
      priority       = 100,
      service        = { id = another_uuid },
    }

    local expressions = {
      [[http.path.segments.0 == "foo"]],
      [[http.path.segments.1 ^= "bar"]],
      [[http.path.segments.20_30 ~ r#"x/y"#]],
      [[http.path.segments.len == 10]],
    }

    for _, exp in ipairs(expressions) do
      r.expression = exp

      local route = Routes:process_auto_fields(r, "insert")
      assert.truthy(Routes:validate(route))
    end

  end)

  it("fails if http route has invalid http.path.segments.* fields", function()
    local r = {
      id             = a_valid_uuid,
      name           = "my_route",
      protocols      = { "http" },
      priority       = 100,
      service        = { id = another_uuid },
    }

    local wrong_expressions = {
      [[http.path.segments.len0   == 10]],
      [[http.path.segments.len_a  == 10]],
      [[http.path.segments.len    == "10"]],

      [[http.path.segments.       == "foo"]],
      [[http.path.segments.abc    == "foo"]],
      [[http.path.segments.a_c    == "foo"]],
      [[http.path.segments.1_2_3  == "foo"]],
      [[http.path.segments.1_     == "foo"]],
      [[http.path.segments._1     == "foo"]],
      [[http.path.segments.2_1    == "foo"]],
      [[http.path.segments.1_1    == "foo"]],
      [[http.path.segments.01_2   == "foo"]],
      [[http.path.segments.001_2  == "foo"]],
      [[http.path.segments.1_03   == "foo"]],
    }

    for _, exp in ipairs(wrong_expressions) do
      r.expression = exp

      local route = Routes:process_auto_fields(r, "insert")
      local ok, errs = Routes:validate_insert(route)
      assert.falsy(ok)
      assert.truthy(errs["@entity"])
    end
  end)
end)
