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


local function patch(path, body, headers, expected_status)
  headers = headers or {}
  if not headers["Content-Type"] then
    headers["Content-Type"] = "application/json"
  end

  if any(tablex.keys(body), function(x) return x:match( "%[%]$") end) then
    headers["Content-Type"] = "application/x-www-form-urlencoded"
  end

  local res = assert(client:send{
    method = "PATCH",
    path = path,
    body = body or {},
    headers = headers
  })

  return cjson.decode(assert.res_status(expected_status or 200, res))
end


for _, strategy in helpers.each_strategy() do
describe("DB [".. strategy .. "] sharing ", function()
  setup(function()
    helpers.get_db_utils(strategy)

    assert(helpers.start_kong({
      database = strategy,
    }))

    client = assert(helpers.admin_client())

    post("/workspaces", {name = "ws1"})
    post("/workspaces", {name = "ws2"})
    post("/workspaces", {name = "ws3"})
  end)

  it("is allowed from the workspace where the entity lives", function()
    -- create consumer in default workspace
    local c1 = post("/consumers", {username = "c1"})
    -- share it with ws1, from default workspace
    post("/workspaces/ws1/entities", {entities = c1.id})
  end)

  it("is not allowed from a workspace that doesn't own the entity", function()
    -- create consumer in ws1 workspace
    local c2 = post("/ws1/consumers", {username = "c2"})
    -- try to share it from default, while it is in ws1
    post("/workspaces/ws2/entities", {entities = c2.id}, nil, 404)
    -- try to share it from ws3, where neither the entity nor ws1 belong to
    post("/ws3/workspaces/ws2/entities", {entities = c2.id}, nil, 404)
  end)

  teardown(function()
    helpers.stop_kong()
    client:close()
  end)
end)

describe("DB [".. strategy .. "] routes are checked for colisions ", function()
  local route, default_service
  setup(function()
    helpers.get_db_utils(strategy)

    assert(helpers.start_kong({
      database   = strategy,
    }))

    client = assert(helpers.admin_client())

    post("/workspaces", {name = "ws1"})
    post("/workspaces", {name = "ws2"})
    default_service = post("/ws1/services", {name = "default-service", host = "httpbin1.org"})
    post("/ws2/services", {name = "default-service", host = "httpbin2.org"})
    route = post("/ws1/services/default-service/routes", {['hosts[]'] = "example.org"})
  end)

  teardown(function()
    helpers.stop_kong()
    client:close()
  end)

  it("returns 400 on invalid requests", function()
    local res = assert(client:send{
      method = "POST",
      path = "/ws2/services/default-service/routes",
      body = '{"protocols":["http"],"methods":["GET"],"hosts":[],"paths":[null],"strip_path":true,"preserve_host":false,"service":{"id":"'.. default_service.id .. '"}}',
      headers = {["Content-Type"] = "application/json"}
    })
    return cjson.decode(assert.res_status(400, res))
  end)

  it("collides when 1 route swallows traffic from  different ws", function()
    post("/ws2/services/default-service/routes",
      {['hosts[]'] = "example.org"}, nil, 409)
    post("/ws2/services/nonexistent/routes",
      {['hosts[]'] = "example.org"}, nil, 404)
  end)

  it("doesnt collide if we are in the same ws", function()
    post("/ws1/services/default-service/routes",
      {['hosts[]'] = "example.org"})
  end)

  it("doesnt collide for distinct routes", function()
    post("/ws2/services/default-service/routes",
      {['hosts[]'] = "new-host.org"})
  end)

  it("can be updated with patch", function()
    patch("/ws1/routes/".. route.id, {["protocols[]"] = "http"})
  end)

  it("collides when updating", function()
    local r = post("/ws2/services/default-service/routes",
      {['hosts[]'] = "bla.org"})
    patch("/ws2/routes/" .. r.id, {['hosts[]'] = "example.org"}, nil, 409)
  end)
end)
end
