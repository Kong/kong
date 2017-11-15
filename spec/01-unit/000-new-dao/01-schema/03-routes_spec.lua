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
      paths          = { "/", "/ovo" },
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
      { true, { protocols = { "http" }, service = s, paths = {"/"} },     {"methods", "hosts"} },
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
      paths = { "/" }
    }
    route = Routes:process_auto_fields(route, "insert")
    local ok, err = Routes:validate(route)
    assert.is_nil(err)
    assert.truthy(ok)
    assert.match(uuid_pattern, route.id)
    assert.same(route.protocols, { "http" })
    assert.same(route.methods, ngx.null)
    assert.same(route.hosts, ngx.null)
    assert.same(route.paths, { "/" })
    assert.same(route.regex_priority, 0)
    assert.same(route.strip_path, false)
    assert.same(route.preserve_host, false)
  end)

  it("validates the foreign key in entities", function()
    local route = {
      protocols = { "http" },
      paths = { "/" },
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


end)
