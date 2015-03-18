local yaml = require "yaml"
local utils = require "kong.tools.utils"
local spec_helper = require "spec.spec_helpers"
local constants = require "kong.constants"
local stringy = require "stringy"

local TEST_CONF = "kong_TEST.yml"
local SERVER_CONF = "kong_TEST_SERVER.yml"

local function replace_conf_property(key, value)
  local yaml_value = yaml.load(utils.read_file(TEST_CONF))
  if type(value) == "table" and utils.table_size(value) == 0 then
    value = nil
  end
  yaml_value[key] = value
  utils.write_to_file(SERVER_CONF, yaml.dump(yaml_value))
end

describe("Server", function()

  describe("CLI", function()

    it("should return the right version", function()
      local result, exit_code = spec_helper.os_execute(spec_helper.KONG_BIN.." -v")
      assert.are.same("Version: "..constants.VERSION, stringy.strip(result))
    end)

  end)

  describe("Startup migration", function()

    setup(function()
      local databases_available = yaml.load(utils.read_file(TEST_CONF)).databases_available
      databases_available.cassandra.properties.keyspace = "kong_tests_server_migrations"
      replace_conf_property("databases_available", databases_available)
      spec_helper.add_env(SERVER_CONF)
    end)

    teardown(function()
      spec_helper.stop_kong(SERVER_CONF)
      spec_helper.reset_db(SERVER_CONF)
      os.remove(SERVER_CONF)
      spec_helper.remove_env(SERVER_CONF)
    end)

    it("should migrate when starting for the first time on a new keyspace", function()
      spec_helper.start_kong(SERVER_CONF)
      local env = spec_helper.get_env(SERVER_CONF)
      local migrations = env.dao_factory:get_migrations()
      assert.True(#migrations > 0)
    end)

  end)

  describe("Startup plugins check", function()

    setup(function()
      os.execute("cp "..TEST_CONF.." "..SERVER_CONF)
      spec_helper.prepare_db()
      spec_helper.drop_db() -- remove the seed from prepare_db()
    end)

    teardown(function()
      os.remove(SERVER_CONF)
    end)

    after_each(function()
      spec_helper.stop_kong(SERVER_CONF)
      spec_helper.reset_db()
    end)

    it("should work when no plugins are enabled and the DB is empty", function()
      replace_conf_property("plugins_available", {})
      local result, exit_code = spec_helper.start_kong(SERVER_CONF, true)
      assert.are.same(0, exit_code)
    end)

    it("should not work when an unexisting plugin is being enabled", function()
      replace_conf_property("plugins_available", {"wot-wat"})

      assert.has_error(function()
        spec_helper.start_kong(SERVER_CONF, true)
      end, "The following plugin has been enabled in the configuration but is not installed on the system: wot-wat")
    end)

    it("should not fail when an existing plugin is being enabled", function()
      replace_conf_property("plugins_available", {"authentication"})

      local result, exit_code = spec_helper.start_kong(SERVER_CONF, true)
      assert.are.same(0, exit_code)
    end)

    it("should not work when an unexisting plugin is being enabled along with an existing one", function()
      replace_conf_property("plugins_available", {"authentication", "wot-wat"})
      assert.has_error(function()
        spec_helper.start_kong(SERVER_CONF, true)
      end, "The following plugin has been enabled in the configuration but is not installed on the system: wot-wat")
    end)

    it("should not work when a plugin is being used in the DB but it's not in the configuration", function()
      replace_conf_property("plugins_available", {"authentication"})
      spec_helper.prepare_db()
      assert.has_error(function()
        spec_helper.start_kong(SERVER_CONF, true)
      end, "You are using a plugin that has not been enabled in the configuration: ratelimiting")
    end)

    it("should work the used plugins are enabled", function()
      replace_conf_property("plugins_available", {"ratelimiting", "authentication"})
      local result, exit_code = spec_helper.start_kong(SERVER_CONF, true)
      assert.are.same(0, exit_code)
    end)

  end)
end)
