-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local helpers = require "spec.helpers"
local cjson = require "cjson"

local client


local function send_request(method, default_status, path, body, expected_status, headers)
  headers = headers or {}
  if not headers["Content-Type"] then
    headers["Content-Type"] = "application/json"
  end

  local res = assert(client:send{
    method = method,
    path = path,
    body = body or {},
    headers = headers
  })
  return cjson.decode(assert.res_status(expected_status or default_status, res))
end


local function post(path, body, expected_status, headers)
  return send_request("POST", 201, path, body, expected_status, headers)
end
local function patch(path, body, expected_status, headers)
  return send_request("PATCH", 200, path, body, expected_status, headers)
end
local function put(path, body, expected_status, headers)
  return send_request("PUT", 200, path, body, expected_status, headers)
end


local strategy = "postgres"
describe("DB [#" .. strategy .. "] static strategy: routes are checked for colisions", function()
  local _, db, service_ws2
  setup(function()
    _, db = helpers.get_db_utils(strategy)

    assert(helpers.start_kong({
      database   = strategy,
      route_validation_strategy = "static",
    }))

    client = assert(helpers.admin_client())
    post("/workspaces", {name = "ws1"})
    post("/workspaces", {name = "ws2"})
  end)

  teardown(function()
    helpers.stop_kong()
    client:close()
  end)

  before_each(function()
    post("/ws1/services", {name = "default-service", host = "httpbin1.test"})
    service_ws2 = post("/ws2/services", {name = "ws2-service", host = "httpbin2.test"})
  end)

  after_each(function()
    assert(db:truncate("routes"))
    assert(db:truncate("services"))
  end)

  it("detects collisions if paths, hosts and methods overlap null entries", function()
    -- add a route that has paths, hosts and methods null
    post("/ws2/services/ws2-service/routes", '{"name": "route1", "headers": {"location": ["route1"]}}')
    post("/ws2/services/ws2-service/routes", '{"name": "route2", "headers": {"location": ["route2"]}}', 409)
    post("/ws2/services/ws2-service/routes", '{"name": "route2", "paths": null}', 409)
    post("/ws2/services/ws2-service/routes", '{"name": "route2", "paths": []}', 409)
    post("/ws2/services/ws2-service/routes", '{"name": "route2", "hosts": null}', 409)
    post("/ws2/services/ws2-service/routes", '{"name": "route2", "hosts": []}', 409)
    post("/ws2/services/ws2-service/routes", '{"name": "route2", "methods": null}', 409)
    post("/ws2/services/ws2-service/routes", '{"name": "route2", "methods": []}', 409)
    post("/ws2/services/ws2-service/routes", '{"name": "route2", "paths": null, "hosts": null, "methods": []}', 409)
    post("/ws2/services/ws2-service/routes", '{"name": "route2", "paths": [], "hosts": [], "methods": []}', 409)
  end)

  it("detects collisions if paths overlap", function()
    post("/ws2/services/ws2-service/routes", '{"name": "route1", "paths": ["/route1"]}')
    post("/ws2/services/ws2-service/routes", '{"name": "route2", "paths": ["/route1"]}', 409)

    post("/ws2/services/ws2-service/routes", '{"name": "route2", "paths": ["/route2", "/route2-tmp"]}')
    post("/ws2/services/ws2-service/routes", '{"name": "route3", "paths": ["/route2"]}', 409)
    post("/ws2/services/ws2-service/routes", '{"name": "route3", "paths": ["/route2-tmp", "/routenotused"]}', 409)
    post("/ws2/services/ws2-service/routes", '{"name": "route3", "paths": ["/routenotused", "/route2-tmp"]}', 409)
  end)

  it("detects collisions if hosts overlap", function()
    post("/ws2/services/ws2-service/routes", '{"name": "route1", "hosts": ["route1.test"]}')
    post("/ws2/services/ws2-service/routes", '{"name": "route2", "hosts": ["route1.test"]}', 409)

    post("/ws2/services/ws2-service/routes", '{"name": "route2", "hosts": ["route2.test", "dev.route2.test"]}')
    post("/ws2/services/ws2-service/routes", '{"name": "route3", "hosts": ["route2.test"]}', 409)
    post("/ws2/services/ws2-service/routes", '{"name": "route3", "hosts": ["dev.route2.test", "tmp.route2.test"]}', 409)
    post("/ws2/services/ws2-service/routes", '{"name": "route3", "hosts": ["tmp.route2.test", "dev.route2.test"]}', 409)
  end)

  it("detects collisions if methods overlap", function()
    post("/ws2/services/ws2-service/routes", '{"name": "route1", "methods": ["GET", "POST"]}')
    post("/ws2/services/ws2-service/routes", '{"name": "route2", "methods": ["GET"]}', 409)

    post("/ws2/services/ws2-service/routes", '{"name": "route2", "methods": ["PUT", "PATCH"]}')
    post("/ws2/services/ws2-service/routes", '{"name": "route3", "methods": ["PUT"]}', 409)
    post("/ws2/services/ws2-service/routes", '{"name": "route3", "methods": ["PATCH", "DELETE"]}', 409)
    post("/ws2/services/ws2-service/routes", '{"name": "route3", "methods": ["DELETE", "PATCH"]}', 409)
  end)

  it("detects collisions with a route using default methods (null=all methods)", function()
    -- methods == null means all methods
    post("/ws2/services/ws2-service/routes", '{"name": "route1", "headers": {"location": ["route1"]}}')
    post("/ws2/services/ws2-service/routes", '{"name": "route2", "methods": ["GET"]}', 409)
    post("/ws2/services/ws2-service/routes", '{"name": "route3", "methods": ["POST"]}', 409)
    post("/ws2/services/ws2-service/routes", '{"name": "route4", "methods": ["PUT"]}', 409)
    post("/ws2/services/ws2-service/routes", '{"name": "route5", "methods": ["PATCH"]}', 409)
    post("/ws2/services/ws2-service/routes", '{"name": "route6", "methods": ["DELETE"]}', 409)
    post("/ws2/services/ws2-service/routes", '{"name": "route7", "methods": ["OPTIONS"]}', 409)

    post("/ws2/services/ws2-service/routes",
      '{"name": "route2", "paths":["/test"], "methods": ["GET","POST","PUT","PATCH","DELETE","OPTIONS"]}')
    post("/ws2/services/ws2-service/routes", '{"name": "route3", "paths":["/test"]}', 409)
  end)

  it("detects collisions with a route using default paths (null=/)", function()
    -- paths == null means /
    post("/ws2/services/ws2-service/routes", '{"name": "route1", "headers": {"location": ["route1"]}}')
    post("/ws2/services/ws2-service/routes", '{"name": "route2", "paths": ["/"]}', 409)

    post("/ws2/services/ws2-service/routes", '{"name": "route2", "paths": ["/"], "hosts": ["example.com"]}')
    post("/ws2/services/ws2-service/routes", '{"name": "route3", "hosts": ["example.com"]}', 409)
  end)

  it("detects no collision if one of paths, hosts or methods differ", function()
    post("/ws2/services/ws2-service/routes", '{"name": "route1", "paths": ["/route1"], "methods": ["GET"], "hosts": ["example.com"]}')
    post("/ws2/services/ws2-service/routes", '{"name": "route2", "paths": ["/route1"], "methods": ["GET"], "hosts": ["example.com"]}', 409)

    post("/ws2/services/ws2-service/routes", '{"name": "route2", "paths": ["/route2"], "methods": ["GET"], "hosts": ["example.com"]}')
    post("/ws2/services/ws2-service/routes", '{"name": "route3", "paths": ["/route1"], "methods": ["POST"], "hosts": ["example.com"]}')
    post("/ws2/services/ws2-service/routes", '{"name": "route4", "paths": ["/route1"], "methods": ["GET"], "hosts": ["dev.example.com"]}')

    post("/ws2/services/ws2-service/routes", '{"name": "route5", "paths": null, "methods": ["GET"], "hosts": ["example.com"]}')
    -- special case here because null means all methods... so automatic collision
    post("/ws2/services/ws2-service/routes", '{"name": "route6", "paths": ["/route1"], "methods": null, "hosts": ["example.com"]}', 409)
    post("/ws2/services/ws2-service/routes", '{"name": "route7", "paths": ["/route1"], "methods": ["GET"], "hosts": ["stage.example.com"]}')
  end)

  it("detects collisions across all workspace", function()
    post("/ws1/services/default-service/routes", '{"name": "route1", "paths": ["/route1"]}')
    post("/ws2/services/ws2-service/routes", '{"name": "route2", "paths": ["/route1"]}', 409)
  end)

  it("returns the route of the collision on conflict", function()
    post("/ws2/services/ws2-service/routes", '{"name": "route1", "paths": ["/route1"]}')
    local res = post("/ws2/services/ws2-service/routes", '{"name": "route1", "paths": ["/route1"]}', 409)
    assert.equals(res.collision.existing_route.name, "route1")
    assert.equals(res.collision.request.paths[1], "/route1")
    assert.is_string(res.collision.existing_route.service.id)
    assert.is_string(res.collision.existing_route.ws_id)
  end)

  it("detects collisions with all api endpoints", function()
    post("/ws2/services/ws2-service/routes", '{"name": "route1", "paths": ["/route1"]}')
    post("/ws2/services/ws2-service/routes", '{"name": "route2", "paths": ["/route2"]}')

    post("/ws2/services/ws2-service/routes", '{"name": "route3", "paths": ["/route2"]}', 409)
    patch("/ws2/services/ws2-service/routes/route1", '{"paths": ["/route2"]}', 409)
    --put("/ws2/services/ws2-service/routes/route1", '{"paths": ["/route2"]}', 409)

    post("/ws2/routes", '{"service": {"id": "' .. service_ws2.id .. '"}, "name": "route3", "paths": ["/route1"]}', 409)
    put("/ws2/routes/route1", '{"service": {"id": "' .. service_ws2.id .. '"}, "paths": ["/route2"]}', 409)
    patch("/ws2/routes/route1", '{"service": {"id": "' .. service_ws2.id .. '"}, "paths": ["/route2"]}', 409)
  end)

  it("does not detect a collision when patching the same route", function()
    post("/ws2/services/ws2-service/routes", '{"name": "route1", "paths": ["/route1"]}')
    post("/ws2/services/ws2-service/routes", '{"name": "route2", "paths": ["/route2"]}')
    -- OK
    patch("/ws2/services/ws2-service/routes/route1", '{"name": "route1", "paths": ["/route1"]}', 200)
    -- not OK
    patch("/ws2/services/ws2-service/routes/route1", '{"name": "route1", "paths": ["/route2"]}', 409)
  end)
end)
