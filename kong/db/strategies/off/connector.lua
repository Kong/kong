local meta = require "kong.meta"


local OffConnector   = {}
OffConnector.__index = OffConnector


local function ignore()
  return true
end


function OffConnector.new(kong_config)
  local self = {
    timeout = 1,
    close = ignore,
    connect = ignore,
    truncate_table = ignore,
    truncate = ignore,
  }

  return setmetatable(self, OffConnector)
end


function OffConnector:infos()
  return {
    strategy = "off",
    db_name = "kong_off",
    db_desc = "cache",
    db_ver = meta._VERSION,
  }
end


function OffConnector:connect_migrations(opts)
  -- FIXME what is this used for, again?
  return {}
end


function OffConnector:query()
  return nil, "cannot perform queries without a database"
end


do
  -- migrations


  function OffConnector:schema_migrations()
    -- TODO this could be built dynamically by scanning the filesystem
    local rows = {
      { subsystem = "core", executed = { "000_base", "001_14_to_15", "002_15_to_1", "003_100_to_110" } },
      { subsystem = "rate-limiting", executed = { "000_base_rate_limiting", "001_14_to_15", "002_15_to_10" } },
      { subsystem = "hmac-auth", executed = { "000_base_hmac_auth", "001_14_to_15" } },
      { subsystem = "oauth2", executed = { "000_base_oauth2", "001_14_to_15", "002_15_to_10" } },
      { subsystem = "jwt", executed = { "000_base_jwt", "001_14_to_15" } },
      { subsystem = "basic-auth", executed = { "000_base_basic_auth", "001_14_to_15" } },
      { subsystem = "key-auth", executed = { "000_base_key_auth", "001_14_to_15" } },
      { subsystem = "acl", executed = { "000_base_acl", "001_14_to_15" } },
      { subsystem = "response-ratelimiting", executed = { "000_base_response_rate_limiting", "001_14_to_15", "002_15_to_10" } },
    }
    for _, row in ipairs(rows) do
      row.last_executed = row.executed[#row.executed]
      row.pending = {}
    end
    return rows
  end


  function OffConnector:is_014()
    return {
      is_014 = false,
    }
  end
end


function OffConnector:get_timeout()
  return self.timeout
end


return OffConnector
