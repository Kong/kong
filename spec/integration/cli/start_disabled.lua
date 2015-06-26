local spec_helper = require "spec.spec_helpers"
local utils = require "kong.tools.utils"
local yaml = require "yaml"
local IO = require "kong.tools.io"

local TEST_CONF = spec_helper.get_env().conf_file
local SERVER_CONF = "kong_TEST_SERVER.yml"

local function replace_conf_property(key, value)
  local yaml_value = yaml.load(IO.read_file(TEST_CONF))
  if type(value) == "table" and utils.table_size(value) == 0 then
    value = nil
  end
  yaml_value[key] = value
  local ok = IO.write_to_file(SERVER_CONF, yaml.dump(yaml_value))
  assert.truthy(ok)
end

describe("CLI", function()

  describe("Startup plugins check", function()

    setup(function()
      os.execute("cp "..TEST_CONF.." "..SERVER_CONF)
      spec_helper.add_env(SERVER_CONF)
      spec_helper.prepare_db(SERVER_CONF)
    end)

    teardown(function()
      os.remove(SERVER_CONF)
      spec_helper.remove_env(SERVER_CONF)
    end)

    after_each(function()
      pcall(spec_helper.stop_kong, SERVER_CONF)
    end)

    it("should start with the default configuration", function()
      assert.has_no.errors(function()
        spec_helper.start_kong(TEST_CONF, true)
      end)

      finally(function()
        pcall(spec_helper.stop_kong, TEST_CONF)
      end)
    end)

    it("should work when no plugins are enabled and the DB is empty", function()
      replace_conf_property("plugins_available", {})

      local _, exit_code = spec_helper.start_kong(SERVER_CONF, true)
      assert.are.same(0, exit_code)
    end)

    it("should not work when an unexisting plugin is being enabled", function()
      replace_conf_property("plugins_available", {"wot-wat"})

      assert.has_error(function()
        spec_helper.start_kong(SERVER_CONF, true)
      end, "The following plugin has been enabled in the configuration but it is not installed on the system: wot-wat")
    end)

    it("should not fail when an existing plugin is being enabled", function()
      replace_conf_property("plugins_available", {"keyauth"})

      local _, exit_code = spec_helper.start_kong(SERVER_CONF, true)
      assert.are.same(0, exit_code)
    end)

    it("should not work when an unexisting plugin is being enabled along with an existing one", function()
      replace_conf_property("plugins_available", {"keyauth", "wot-wat"})

      assert.has_error(function()
        spec_helper.start_kong(SERVER_CONF, true)
      end, "The following plugin has been enabled in the configuration but it is not installed on the system: wot-wat")
    end)

    it("should not work when a plugin is being used in the DB but it's not in the configuration", function()
      spec_helper.get_env(SERVER_CONF).faker:insert_from_table {
        api = {
          { name = "tests cli 1", public_dns = "foo.com", target_url = "http://mockbin.com" },
        },
        plugin_configuration = {
          { name = "ratelimiting", value = {period = "minute", limit = 6}, __api = 1 },
        }
      }

      replace_conf_property("plugins_available", {"ssl", "keyauth", "basicauth", "oauth2", "tcplog", "udplog", "filelog", "httplog", "request_transformer", "cors"})

      assert.has_error(function()
        spec_helper.start_kong(SERVER_CONF, true)
      end, "You are using a plugin that has not been enabled in the configuration: ratelimiting")
    end)

    it("should work the used plugins are enabled", function()
      replace_conf_property("plugins_available", {"ssl", "keyauth", "basicauth", "oauth2", "tcplog", "udplog", "filelog", "httplog", "request_transformer", "ratelimiting", "cors"})

      local _, exit_code = spec_helper.start_kong(SERVER_CONF, true)
      assert.are.same(0, exit_code)
    end)

  end)
end)
