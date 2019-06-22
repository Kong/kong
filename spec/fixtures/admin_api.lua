local blueprints = require "spec.fixtures.blueprints"
local helpers = require "spec.helpers"
local cjson = require "cjson"


local function api_send(method, path, body, forced_port)
  local api_client = helpers.admin_client(nil, forced_port)
  local res, err = api_client:send({
    method = method,
    path = path,
    headers = {
      ["Content-Type"] = "application/json"
    },
    body = body,
  })
  if not res then
    api_client:close()
    return nil, err
  end

  if res.status == 204 then
    api_client:close()
    return nil
  end

  local resbody = res:read_body()
  api_client:close()
  if res.status < 300 then
    return cjson.decode(resbody)
  end

  return nil, "Error " .. tostring(res.status) .. ": " .. resbody
end


local admin_api_as_db = {}

for name, dao in pairs(helpers.db.daos) do
  local admin_api_name = dao.schema.admin_api_name or name
  admin_api_as_db[name] = {
    insert = function(_, tbl)
      return api_send("POST", "/" .. admin_api_name, tbl)
    end,
    remove = function(_, tbl)
      return api_send("DELETE", "/" .. admin_api_name .. "/" .. tbl.id)
    end,
    update = function(_, id, tbl)
      return api_send("PATCH", "/" .. admin_api_name .. "/" .. id, tbl)
    end,
  }
end


admin_api_as_db["basicauth_credentials"] = {
  insert = function(_, tbl)
    return api_send("POST", "/consumers/" .. tbl.consumer.id .. "/basic-auth", tbl)
  end,
  remove = function(_, tbl)
    return api_send("DELETE", "/consumers/" .. tbl.consumer.id .. "/basic-auth/" .. tbl.id)
  end,
  update = function(_, id, tbl)
    return api_send("PATCH", "/consumers/" .. tbl.consumer.id .. "/basic-auth/" .. id, tbl)
  end,
}

admin_api_as_db["targets"] = {
  insert = function(_, tbl)
    return api_send("POST", "/upstreams/" .. tbl.upstream.id .. "/targets", tbl)
  end,
  remove = function(_, tbl)
    return api_send("DELETE", "/upstreams/" .. tbl.upstream.id .. "/targets/" .. tbl.id)
  end,
  update = function(_, id, tbl)
    return api_send("PATCH", "/upstreams/" .. tbl.upstream.id .. "/targets/" .. id, tbl)
  end,
}


return blueprints.new(admin_api_as_db)
