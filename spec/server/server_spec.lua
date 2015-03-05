local yaml = require "yaml"
local utils = require "kong.tools.utils"

local TEST_CONF = "kong_TEST.yml"
local SERVER_CONF = "kong_TEST_SERVER.yml"

local function replace_conf_property(name, value)
  local yaml_value = yaml.load(utils.read_file(TEST_CONF))
  yaml_value[name] = value
  utils.write_to_file(SERVER_CONF, yaml.dump(yaml_value))
end

local function result_contains(result, val)
  return result:find(val, 1, true)
end

describe("#server-cli", function()
  --[[
  describe("Plugins Check", function()

    setup(function()
      os.execute("cp "..TEST_CONF.." "..SERVER_CONF)
    end)

    teardown(function()
      os.execute("rm "..SERVER_CONF)
    end)

    before_each(function()
      stop_server()
      dao_factory:drop()
    end)

    after_each(function()
      stop_server()
    end)

    it("should work when no plugins are enabled and the DB is empty", function()
      replace_conf_property("plugins_enabled", {})
      local result, exit_code = start_server()
      assert.are.same(0, exit_code)
    end)

    it("should not work when an unexisting plugin is being enabled", function()
      replace_conf_property("plugins_enabled", {"wot-wat"})
      local result, exit_code = start_server()
      if exit_code == 1 then
        assert.truthy(result_contains(result, "The following plugin is being used but it's not installed in the system: wot-wat"))
      else
        -- The test should fail here
        assert.truthy(false)
      end
    end)

    it("should not fail when an existing plugin is being enabled", function()
      replace_conf_property("plugins_enabled", {"authentication"})
      local result, exit_code = start_server()
      assert.are.same(0, exit_code)
    end)

    it("should not work when an unexisting plugin is being enabled along with an existing one", function()
      replace_conf_property("plugins_enabled", {"authentication", "wot-wat"})
      local result, exit_code = start_server()
      if exit_code == 1 then
        assert.truthy(result_contains(result, "The following plugin is being used but it's not installed in the system: wot-wat"))
      else
        -- The test should fail here
        assert.truthy(false)
      end
    end)

    it("should not work when an unexisting plugin is being enabled along with an existing one", function()
      local faker = Faker(dao_factory)
      faker:seed()
      replace_conf_property("plugins_enabled", {"authentication"})
      local result, exit_code = start_server()

      print(result)

      if exit_code == 1 then
        assert.truthy(result_contains(result, "The following plugin is being used but it's not installed in the system: wot-wat"))
      else
        -- The test should fail here
        assert.truthy(false)
      end
    end)

  end)
  --]]
end)
