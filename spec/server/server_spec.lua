local yaml = require "yaml"

local CassandraFactory = require "kong.dao.cassandra.factory"
local utils = require "kong.tools.utils"

local configuration, dao_factory = utils.load_configuration_and_dao("kong_TEST.yml")

local TEST_CONF = "kong_TEST.yml"
local SERVER_CONF = "kong_TEST_SERVER.yml"
local KONG_BIN = "bin/kong"
local DB_BIN = "scripts/db.lua"

local function execute(command)
  -- returns success, error code, output.
  local f = io.popen(command..' 2>&1 && echo " $?"')
  local output = f:read"*a"
  local begin, finish, code = output:find" (%d+)\n$"
  output, code = output:sub(1, begin -1), tonumber(code)
  return code == 0 and true or false, code, output
end

local function restart_server()
  return execute(KONG_BIN.." -c "..SERVER_CONF.." restart")
end

local function replace_conf_property(name, value)

  local inspect = require "inspect"
  print(inspect(configuration))

  configuration[name] = value
  utils.write_to_file(SERVER_CONF, yaml.dump(configuration))
end

describe("Server #server", function()

  describe("Plugins Check", function()

    setup(function()
      os.execute("cp "..TEST_CONF.." "..SERVER_CONF)
    end)

    teardown(function()
      --os.execute("rm "..SERVER_CONF)
    end)

    before_each(function()
      dao_factory:drop()
    end)

    it("should work when no plugins are enabled and the DB is empty", function()
      replace_conf_property("plugins_enabled", {"wot-wat"})
      local success, code, output = restart_server()

      local inspect = require "inspect"
      print(inspect(success))
      print(inspect(code))
      print(inspect(output))

    end)

  end)

end)
