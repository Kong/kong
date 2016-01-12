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

  describe("Startup plugins check", function()

    it("should start with the default configuration", function()
      assert.has_no.errors(function()
        spec_helper.start_kong(TEST_CONF, true)
      end)

      finally(function()
        pcall(spec_helper.stop_kong, TEST_CONF)
      end)
    end)

    it("should work when no plugins are enabled and the DB is empty", function()
      replace_conf_property("custom_plugins", {})

      local _, exit_code = spec_helper.start_kong(SERVER_CONF, true)
      assert.are.same(0, exit_code)
    end)

    it("should not work when an unexisting plugin is being enabled", function()
      replace_conf_property("custom_plugins", {"wot-wat"})

      assert.error_matches(function()
        spec_helper.start_kong(SERVER_CONF, true)
      end, "The following plugin has been enabled in the configuration but it is not installed on the system: wot-wat", nil, true)
    end)

    it("should not fail when an existing plugin is being enabled", function()
      replace_conf_property("custom_plugins", {"key-auth"})

      local _, exit_code = spec_helper.start_kong(SERVER_CONF, true)
      assert.are.same(0, exit_code)
    end)

    it("should not work when an unexisting plugin is being enabled along with an existing one", function()
      replace_conf_property("custom_plugins", {"key-auth", "wot-wat"})

      assert.error_matches(function()
        spec_helper.start_kong(SERVER_CONF, true)
      end, "The following plugin has been enabled in the configuration but it is not installed on the system: wot-wat", nil, true)
    end)

    it("should work when a default plugin is being used in the DB but it's not explicit in the configuration", function()
      spec_helper.get_env(SERVER_CONF).faker:insert_from_table {
        api = {
          {name = "tests-cli", request_host = "foo.com", upstream_url = "http://mockbin.com"},
        },
        plugin = {
          {name = "rate-limiting", config = {minute = 6}, __api = 1},
        }
      }

      replace_conf_property("custom_plugins", {"ssl", "key-auth", "basic-auth", "oauth2", "tcp-log", "udp-log", "file-log", "http-log", "request-transformer", "cors"})

      local _, exit_code = spec_helper.start_kong(SERVER_CONF, true)
      assert.are.same(0, exit_code)
    end)

    it("should not work when a plugin is being used in the DB but it's not in the configuration", function()
      local cassandra = require "cassandra"

      -- Load everything we need from the spec_helper
      local env = spec_helper.get_env(SERVER_CONF)
      local faker = env.faker
      local dao_factory = env.dao_factory
      local configuration = env.configuration

      local session, err = cassandra.spawn_session {
        shm = "cli_specs",
        keyspace = configuration.dao_config.keyspace,
        contact_points = configuration.dao_config.contact_points
      }
      assert.falsy(err)

      -- Insert API
      local api_t = faker:fake_entity("api")
      local api, err = dao_factory.apis:insert(api_t)
      assert.falsy(err)
      assert.truthy(api.id)

      -- Insert plugin
      local res, err = session:execute("INSERT INTO plugins(id, name, api_id, config) VALUES(uuid(), 'custom-rate-limiting', "..api.id..", '{}')")
      assert.falsy(err)
      assert.truthy(res)

      session:shutdown()

      replace_conf_property("custom_plugins", {})

      assert.error_matches(function()
        spec_helper.start_kong(SERVER_CONF, true)
      end, "You are using a plugin that has not been enabled in the configuration: custom-rate-limiting", nil, true)
    end)

  end)
end)
