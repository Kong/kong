local spec_helpers = require "spec.helpers"
local conf_loader = require "kong.conf_loader"

local DATABASES = { "postgres", "cassandra" }
local env_var = os.getenv("KONG_DATABASE")
if env_var then
  DATABASES = { env_var }
end

local function for_each_dao(fn)
  for i = 1, #DATABASES do
    local database_name = DATABASES[i]
    local conf = assert(conf_loader(spec_helpers.test_conf_path, {
      database = database_name
    }))
    fn(conf)
  end
end

return {
  for_each_dao = for_each_dao
}
