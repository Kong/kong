local yaml = require "yaml"
local utils = require "kong.tools.utils"
local spec_helper = require "spec.spec_helpers"

local TEST_CONF = "kong_TEST.yml"
local SERVER_CONF = "kong_TEST_SERVER.yml"

local function replace_conf_property(name, value)
  local yaml_value = yaml.load(utils.read_file(TEST_CONF))
  if type(value) == "table" and utils.table_size(value) == 0 then
    value = nil
  end
  yaml_value[name] = value
  utils.write_to_file(SERVER_CONF, yaml.dump(yaml_value))
end

local function result_contains(result, val)
  return result:find(val, 1, true)
end

describe("#server-cli", function()

  describe("Plugins Check", function()

    setup(function()
      os.execute("cp "..TEST_CONF.." "..SERVER_CONF)
      spec_helper.prepare_db()
    end)

    teardown(function()
      os.execute("rm "..SERVER_CONF)
      spec_helper.reset_db()
    end)

    before_each(function()
      spec_helper.stop_kong(SERVER_CONF)
      spec_helper.drop_db()
    end)

    after_each(function()
      spec_helper.stop_kong(SERVER_CONF)
    end)

    it("should work when no plugins are enabled and the DB is empty", function()
      replace_conf_property("plugins_enabled", {})
      local result, exit_code = spec_helper.start_kong(SERVER_CONF, true)
      assert.are.same(0, exit_code)
    end)

    it("should not work when an unexisting plugin is being enabled", function()
      replace_conf_property("plugins_enabled", {"wot-wat"})
      local result, exit_code = spec_helper.start_kong(SERVER_CONF, true)
      if exit_code == 1 then
        assert.truthy(result_contains(result, "The following plugin has been enabled in the configuration but is not installed on the system: wot-wat"))
      else
        -- The test should fail here
        assert.truthy(false)
      end
    end)

    it("should not fail when an existing plugin is being enabled", function()
      replace_conf_property("plugins_enabled", {"authentication"})
      local result, exit_code = spec_helper.start_kong(SERVER_CONF, true)
      assert.are.same(0, exit_code)
    end)

    it("should not work when an unexisting plugin is being enabled along with an existing one", function()
      replace_conf_property("plugins_enabled", {"authentication", "wot-wat"})
      local result, exit_code = spec_helper.start_kong(SERVER_CONF, true)
      if exit_code == 1 then
        assert.truthy(result_contains(result, "The following plugin has been enabled in the configuration but is not installed on the system: wot-wat"))
      else
        -- The test should fail here
        assert.truthy(false)
      end
    end)

    it("should not work when a plugin is being used in the DB but it's not in the configuration", function()
      replace_conf_property("plugins_enabled", {"authentication"})
      spec_helper.prepare_db(true)
      local result, exit_code = spec_helper.start_kong(SERVER_CONF, true)
      if exit_code == 1 then
        assert.truthy(result_contains(result, "You are using a plugin that has not been enabled in the configuration: ratelimiting"))
      else
        -- The test should fail here
        assert.truthy(false)
      end
    end)

    it("should work the used plugins are enabled", function()
      replace_conf_property("plugins_enabled", {"ratelimiting", "authentication"})
      spec_helper.prepare_db(true)
      local result, exit_code = spec_helper.start_kong(SERVER_CONF, true)
      assert.are.same(0, exit_code)
    end)

  end)

end)
