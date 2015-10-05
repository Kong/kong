local spec_helper = require "spec.spec_helpers"
local yaml = require "yaml"
local IO = require "kong.tools.io"

local TEST_CONF = spec_helper.get_env().conf_file
local SERVER_CONF = "kong_TEST_SERVER.yml"

local function replace_conf_property(key, value)
  local yaml_value = yaml.load(IO.read_file(TEST_CONF))
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

      assert.error_matches(function()
        spec_helper.start_kong(SERVER_CONF, true)
      end, "The following plugin has been enabled in the configuration but it is not installed on the system: wot-wat", nil, true)
    end)

    it("should not fail when an existing plugin is being enabled", function()
      replace_conf_property("plugins_available", {"key-auth"})

      local _, exit_code = spec_helper.start_kong(SERVER_CONF, true)
      assert.are.same(0, exit_code)
    end)

    it("should not work when an unexisting plugin is being enabled along with an existing one", function()
      replace_conf_property("plugins_available", {"key-auth", "wot-wat"})

      assert.error_matches(function()
        spec_helper.start_kong(SERVER_CONF, true)
      end, "The following plugin has been enabled in the configuration but it is not installed on the system: wot-wat", nil, true)
    end)

    it("should not work when a plugin is being used in the DB but it's not in the configuration", function()
      spec_helper.get_env(SERVER_CONF).faker:insert_from_table {
        api = {
          {name = "tests-cli", request_host = "foo.com", upstream_url = "http://mockbin.com"},
        },
        plugin = {
          {name = "rate-limiting", config = {minute = 6}, __api = 1},
        }
      }

      replace_conf_property("plugins_available", {"ssl", "key-auth", "basic-auth", "oauth2", "tcp-log", "udp-log", "file-log", "http-log", "request-transformer", "cors"})

      assert.error_matches(function()
        spec_helper.start_kong(SERVER_CONF, true)
      end, "You are using a plugin that has not been enabled in the configuration: rate-limiting", nil, true)
    end)

    it("should work the used plugins are enabled", function()
      replace_conf_property("plugins_available", {"ssl", "key-auth", "basic-auth", "oauth2", "tcp-log", "udp-log", "file-log", "http-log", "request-transformer", "rate-limiting", "cors"})

      local _, exit_code = spec_helper.start_kong(SERVER_CONF, true)
      assert.are.same(0, exit_code)
    end)

  end)
end)
