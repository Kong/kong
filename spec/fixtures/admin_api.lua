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

for name, _ in pairs(helpers.db.daos) do
  admin_api_as_db[name] = {
    insert = function(_, tbl)
      local ok, err = api_send("POST", "/" .. name, tbl)
      return ok, err
    end,
    remove = function(_, tbl)
      return api_send("DELETE", "/" .. name .. "/" .. tbl.id)
    end,
  }
end


return blueprints.new(nil, admin_api_as_db)
