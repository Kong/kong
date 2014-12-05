local inspect = require "inspect"
local utils = require "scripts.utils"
local kApenodeWebURL = "http://localhost:8001"

local APIS = {
  {
    public_dns = "httpbin.com",
    target_url = "http://httpbin.org",
    authentication_type = "query"
  },
  {
    public_dns = "httpbin2.com",
    target_url = "http://httpbin.org",
    authentication_type = "query"
  }
}

local APPLICATIONS = {
  {
    account_id = "1234",
    secret_key = "cazzo"
  }
}

function populate(endpoint, entities, entity_name)
  local url = kApenodeWebURL .. endpoint
  for _,entity in pairs(entities) do
    utils.post(url, entity, function(status, body)
      if status == 201 then
        print(entity_name .. " created")
      else
        print("ERROR: " .. status)
      end
    end)
  end
end

populate("/apis/", APIS, "API")
populate("/applications/", APPLICATIONS, "APPLICATION")