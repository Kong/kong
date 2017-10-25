local Schema = require "kong.db.schema"
local services = require "kong.db.schema.entities.services"


local Services = Schema.new(services)


describe("services", function()
  local a_valid_uuid = "cbb297c0-a956-486d-ad1d-f9b42df9465a"
  local uuid_pattern = "^" .. ("%x"):rep(8) .. "%-" .. ("%x"):rep(4) .. "%-"
                           .. ("%x"):rep(4) .. "%-" .. ("%x"):rep(4) .. "%-"
                           .. ("%x"):rep(12) .. "$"


  it("validates a valid service", function()
    local service = {
      id              = a_valid_uuid,
      name            = "my_service",
      protocol        = "http",
      host            = "example.com",
      port            = 80,
      path            = "/foo",
      connect_timeout = 50,
      write_timeout   = 100,
      read_timeout    = 100,
    }
    service = Services:process_auto_fields(service, "insert")
    assert.truthy(Services:validate(service))
  end)

  it("missing protocol produces error", function()
    local service = {
    }
    service = Services:process_auto_fields(service, "insert")
    local ok, errs = Services:validate(service)
    assert.falsy(ok)
    assert.truthy(errs["protocol"])
  end)

  it("invalid protocol produces error", function()
    local service = {
      protocol = "ftp"
    }
    service = Services:process_auto_fields(service, "insert")
    local ok, errs = Services:validate(service)
    assert.falsy(ok)
    assert.truthy(errs["protocol"])
  end)

  it("invalid retries produces error", function()
    local service = Services:process_auto_fields({ retries = -1 }, "insert")
    local ok, errs = Services:validate(service)
    assert.falsy(ok)
    assert.truthy(errs["retries"])
    service = Services:process_auto_fields({ retries = 10000000000 }, "insert")
    local ok, errs = Services:validate(service)
    assert.falsy(ok)
    assert.truthy(errs["retries"])
  end)

  it("produces defaults", function()
    local service = {
      protocol = "http"
    }
    service = Services:process_auto_fields(service, "insert")
    local ok, err = Services:validate(service)
    assert.truthy(ok)
    assert.is_nil(err)
    assert.match(uuid_pattern, service.id)
    assert.same(service.name, ngx.null)
    assert.same(service.protocol, "http")
    assert.same(service.host, ngx.null)
    assert.same(service.port, 80)
    assert.same(service.path, ngx.null)
    assert.same(service.retries, 5)
    assert.same(service.connect_timeout, 60000)
    assert.same(service.write_timeout, 60000)
    assert.same(service.read_timeout, 60000)
  end)
end)
