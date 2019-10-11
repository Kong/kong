local helpers = require "spec.helpers"
local cjson = require "cjson"
local tablex = require "pl.tablex"


local client


local function any(t, p)
  return #tablex.filter(t, p) > 0
end


local function post(path, body, headers, expected_status)
  headers = headers or {}
  if not headers["Content-Type"] then
    headers["Content-Type"] = "application/json"
  end

  if any(tablex.keys(body), function(x) return x:match( "%[%]$") end) then
    headers["Content-Type"] = "application/x-www-form-urlencoded"
  end

  local res = assert(client:send{
    method = "POST",
    path = path,
    body = body or {},
    headers = headers
  })

  return cjson.decode(assert.res_status(expected_status or 201, res))
end


for _, strategy in helpers.each_strategy() do
  describe("DB [".. strategy .. "] routes are checked for enforced pattern", function()
    local ws2_service
    setup(function()
      helpers.get_db_utils(strategy)

      assert(helpers.start_kong({
        database   = strategy,
        route_validation_strategy = "path",
        enforce_route_path_pattern = "/$(workspace)/ver%d/.*"
      }))

      client = assert(helpers.admin_client())

      post("/workspaces", {name = "ws1"})
      post("/workspaces", {name = "ws2"})
      post("/ws1/services", {name = "default-service", host = "httpbin1.org"})
      ws2_service = post("/ws2/services", {name = "ws2-service", host = "httpbin2.org"})
    end)

    teardown(function()
      helpers.stop_kong()
      client:close()
    end)

    it("returns 400 on empty path list", function()
      local res = assert(client:send{
        method = "POST",
        path = "/ws2/services/ws2-service/routes",
        body = '{"protocols":["http"],"methods":["GET"],"hosts":[],"strip_path":true,"preserve_host":false,"service":{"id":"'.. ws2_service.id .. '"}}',
        headers = {["Content-Type"] = "application/json"}
      })
      return cjson.decode(assert.res_status(400, res))
    end)

    it("returns 400 on wrong workspace", function()
      local res = assert(client:send{
        method = "POST",
        path = "/ws2/services/ws2-service/routes",
        body = '{"protocols":["http"],"methods":["GET"],"hosts":[],"paths":["/default/v1/"],"strip_path":true,"preserve_host":false,"service":{"id":"'.. ws2_service.id .. '"}}',
        headers = {["Content-Type"] = "application/json"}
      })
      return cjson.decode(assert.res_status(400, res))
    end)

    it("returns 400 on wrong version", function()
      local res = assert(client:send{
        method = "POST",
        path = "/ws2/services/ws2-service/routes",
        body = '{"protocols":["http"],"methods":["GET"],"hosts":[],"paths":["/ws2/nonver1/"],"strip_path":true,"preserve_host":false,"service":{"id":"'.. ws2_service.id .. '"}}',
        headers = {["Content-Type"] = "application/json"}
      })
      return cjson.decode(assert.res_status(400, res))
    end)

    it("returns 400 on wrong version on endpoint `/routes`", function()
      local res = assert(client:send{
        method = "POST",
        path = "/ws2/routes",
        body = '{"protocols":["http"],"methods":["GET"],"hosts":[],"paths":["/ws2/nonver1/"],"strip_path":true,"preserve_host":false,"service":{"id":"'.. ws2_service.id .. '"}}',
        headers = {["Content-Type"] = "application/json"}
      })
      return cjson.decode(assert.res_status(400, res))
    end)

    it("returns 201 when path matches pattern", function()
      local res = assert(client:send{
        method = "POST",
        path = "/ws2/services/ws2-service/routes",
        body = '{"protocols":["http"],"methods":["GET"],"hosts":[],"paths":["/ws2/ver1/"],"strip_path":true,"preserve_host":false,"service":{"id":"'.. ws2_service.id .. '"}}',
        headers = {["Content-Type"] = "application/json"}
      })
      return cjson.decode(assert.res_status(201, res))
    end)

    it("returns 201 when path matches pattern on endpoint `/routes`", function()
      local res = assert(client:send{
        method = "POST",
        path = "/ws2/routes",
        body = '{"protocols":["http"],"methods":["GET"],"hosts":[],"paths":["/ws2/ver1/"],"strip_path":true,"preserve_host":false,"service":{"id":"'.. ws2_service.id .. '"}}',
        headers = {["Content-Type"] = "application/json"}
      })
      return cjson.decode(assert.res_status(201, res))
    end)

    it("returns 201 when path matches pattern on endpoint `/routes` with PUT", function()
      local res = assert(client:send{
        method = "PUT",
        path = "/ws2/routes/ws2_route",
        body = '{"protocols":["http"],"methods":["GET"],"hosts":[],"paths":["/ws2/ver1/"],"strip_path":true,"preserve_host":false,"service":{"id":"'.. ws2_service.id .. '"}}',
        headers = {["Content-Type"] = "application/json"}
      })
      return cjson.decode(assert.res_status(200, res))
    end)

    pending("returns 400 when path not matches pattern on endpoint `/routes` with PUT", function()
      local res = assert(client:send{
        method = "PUT",
        path = "/ws2/routes/ws2_route",
        body = '{"protocols":["http"],"methods":["GET"],"hosts":[],"paths":["/ws2/v1/"],"strip_path":true,"preserve_host":false,"service":{"id":"'.. ws2_service.id .. '"}}',
        headers = {["Content-Type"] = "application/json"}
      })
      return cjson.decode(assert.res_status(400, res))
    end)

    it("returns 400 when path not matches pattern on endpoint `/routes` with PATCH", function()
      local res = assert(client:send{
        method = "PATCH",
        path = "/ws2/routes/ws2_route",
        body = '{"protocols":["http"],"methods":["GET"],"hosts":[],"paths":["/ws2/v1/"],"strip_path":true,"preserve_host":false,"service":{"id":"'.. ws2_service.id .. '"}}',
        headers = {["Content-Type"] = "application/json"}
      })
      return cjson.decode(assert.res_status(400, res))
    end)

    it("returns 200 when path matches pattern on endpoint `/routes` with PATCH", function()
      local res = assert(client:send{
        method = "PATCH",
        path = "/ws2/routes/ws2_route",
        body = '{"protocols":["http"],"methods":["GET"],"hosts":[],"paths":["/ws2/ver1/"],"strip_path":true,"preserve_host":false,"service":{"id":"'.. ws2_service.id .. '"}}',
        headers = {["Content-Type"] = "application/json"}
      })
      return cjson.decode(assert.res_status(200, res))
    end)

    it("returns 200 when paths is empty with PATCH", function()
      local res = assert(client:send{
        method = "PATCH",
        path = "/ws2/routes/ws2_route",
        body = '{"protocols":["http"],"methods":["GET"],"hosts":[],"paths":[],"strip_path":true,"preserve_host":false,"service":{"id":"'.. ws2_service.id .. '"}}',
        headers = {["Content-Type"] = "application/json"}
      })
      return cjson.decode(assert.res_status(200, res))
    end)
    it("returns 400 when paths is null with PATCH", function()
      local res = assert(client:send{
        method = "PATCH",
        path = "/ws2/routes/ws2_route",
        body = '{"protocols":["http"],"methods":["GET"],"hosts":[],"paths":null,"strip_path":true,"preserve_host":false,"service":{"id":"'.. ws2_service.id .. '"}}',
        headers = {["Content-Type"] = "application/json"}
      })
      return cjson.decode(assert.res_status(400, res))
    end)
  end)
end
