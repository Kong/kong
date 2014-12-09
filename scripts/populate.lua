local utils = require "apenode.utils"
local cjson = require "cjson"
local kApenodeWebURL = "http://localhost:8001"

local APIS = {
  {
    public_dns = "httpbin.com",
    target_url = "http://httpbin.org",
    authentication_type = "query",
    authentication_key_names = "apikey"
  },
  {
    public_dns = "httpbin2.com",
    target_url = "http://httpbin.org",
    authentication_type = "query",
    authentication_key_names = "apikey"
  }
}

local ACCOUNTS = {
  {
    provider_id = "account123"
  }
}

local APPLICATIONS = {
  {
    secret_key = "secret_abcd"
  }
}

function populate(endpoint, entities, entity_name)
  local result = {}
  local url = kApenodeWebURL .. endpoint
  for _,entity in pairs(entities) do
    utils.post(url, entity, function(status, body)
      if status == 201 then
        table.insert(result, cjson.decode(body))
        print(entity_name .. " created")
      else
        print("ERROR: " .. status .. ": " .. body)
      end
    end)
  end
  return result
end

populate("/apis/", APIS, "API")

local accounts = populate("/accounts/", ACCOUNTS, "ACCOUNTS")

-- Assigning the account_id to the applications
for _,v in ipairs(APPLICATIONS) do
  v.account_id = accounts[1].id
end

populate("/applications/", APPLICATIONS, "APPLICATION")