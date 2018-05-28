local dao_helpers = require "spec.02-integration.03-dao.helpers"
local DAOFactory = require "kong.dao.factory"
local helpers = require "spec.helpers"
local cjson = require "cjson"
local utils = require "kong.tools.utils"
local singletons = require "kong.singletons"
local tablex = require "pl.tablex"


local db, dao
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


local function get(path, headers, expected_status)
  headers = headers or {}
  headers["Content-Type"] = "application/json"
  local res = assert(client:send{
    method = "GET",
    path = path,
    headers = headers
  })

  return cjson.decode(assert.res_status(expected_status or 200, res))
end


local function delete(path, headers, expected_status)
  headers = headers or {}
  headers["Content-Type"] = "application/json"
  local res = assert(client:send{
    method = "DELETE",
    path = path,
    body = body or {},
    headers = headers
  })
  assert.res_status(expected_status or 204, res)
end


for _, strategy in helpers.each_strategy() do
describe("DB [".. strategy .. "] routes are checked for colisions ", function()
  local route
  setup(function()
    _, db, dao = helpers.get_db_utils(strategy)
    singletons.dao = dao

    assert(helpers.start_kong({
      database   = strategy,
    }))

    client = assert(helpers.admin_client())

    post("/workspaces", {name = "ws1"})
    post("/workspaces", {name = "ws2"})
    post("/ws1/services", {name = "default-service", host = "httpbin1.org"})
    post("/ws2/services", {name = "default-service", host = "httpbin2.org"})
    route = post("/ws1/services/default-service/routes", {['hosts[]'] = "example.org"})
  end)

  teardown(function()
    helpers.stop_kong()
    client:close()
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
