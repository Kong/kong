local spec_helper = require "spec.spec_helpers"
local yaml = require "yaml"
local IO = require "kong.tools.io"
local http_client = require "kong.tools.http_client"
local Factory = require "kong.dao.factory"

local TEST_CONF = spec_helper.get_env().conf_file
local SERVER_CONF = "kong_TEST_SERVER.yml"

local API_URL = spec_helper.API_URL

local function replace_conf_property(key, value)
  local yaml_value = yaml.load(IO.read_file(TEST_CONF))
  yaml_value[key] = value
  local new_config_content = yaml.dump(yaml_value)
  
  -- Workaround for https://github.com/lubyk/yaml/issues/2
  -- This workaround is in two places. To remove it "Find and replace" in the code
  new_config_content = string.gsub(new_config_content, "(%w+:%s*)([%w%.]+:%d+)", "%1\"%2\"")

  local ok = IO.write_to_file(SERVER_CONF, new_config_content)
  assert.truthy(ok)
end

describe("CLI", function()

  setup(function()
      spec_helper.prepare_db()

      os.execute("cp "..TEST_CONF.." "..SERVER_CONF)
      spec_helper.add_env(SERVER_CONF)
      pcall(spec_helper.stop_kong, TEST_CONF)
      pcall(spec_helper.stop_kong, SERVER_CONF)
    end)

    teardown(function()
      os.remove(SERVER_CONF)
      spec_helper.remove_env(SERVER_CONF)
    end)

    after_each(function()
      pcall(spec_helper.stop_kong, SERVER_CONF)
    end)
  
  describe("Generic", function()
    it("should start up all the services", function()
      assert.has_no.errors(function()
        spec_helper.start_kong(TEST_CONF)
      end)

      local _, status = http_client.get(API_URL)
      assert.equal(200, status) -- is running

      assert.has.errors(function()
        spec_helper.start_kong(TEST_CONF)
      end)

      local _, status = http_client.get(API_URL)
      assert.equal(200, status) -- is running
    end)
  end)
  
  describe("Nodes", function()

    it("should register and de-register the node into the datastore", function()

      assert.has_no.errors(function()
        spec_helper.start_kong(TEST_CONF)
      end)

      local env = spec_helper.get_env() -- test environment
      local dao_factory = env.dao_factory

      local nodes = {}
      local err

      local start = os.time()
      while(#nodes < 1 and (os.time() - start < 10)) do -- 10 seconds timeout
        nodes, err = dao_factory.nodes:find_all()
        assert.falsy(err)
        assert.truthy(nodes)
      end

      assert.truthy(#nodes > 0)

      assert.has_no.errors(function()
        spec_helper.stop_kong(TEST_CONF)
      end)

      nodes = {}

      start = os.time()
      while(#nodes > 0 and (os.time() - start < 10)) do -- 10 seconds timeout
        nodes, err = dao_factory.nodes:find_all()
        assert.falsy(err)
        assert.truthy(nodes)
      end

      assert.truthy(#nodes == 0)
    end)

  end)
  
  describe("Startup plugins check", function()

    it("should start with the default configuration", function()
      assert.has_no.errors(function()
        spec_helper.start_kong(TEST_CONF)
      end)

      finally(function()
        pcall(spec_helper.stop_kong, TEST_CONF)
      end)
    end)

    it("should work when no plugins are enabled and the DB is empty", function()
      replace_conf_property("custom_plugins", {})

      local _, exit_code = spec_helper.start_kong(SERVER_CONF)
      assert.are.same(0, exit_code)
    end)

    it("should not work when an unexisting plugin is being enabled", function()
      replace_conf_property("custom_plugins", {"wot-wat"})

      assert.error_matches(function()
        spec_helper.start_kong(SERVER_CONF)
      end, "The following plugin has been enabled in the configuration but it is not installed on the system: wot-wat", nil, true)
    end)

    it("should not fail when an existing plugin is being enabled", function()
      replace_conf_property("custom_plugins", {"key-auth"})

      local _, exit_code = spec_helper.start_kong(SERVER_CONF)
      assert.are.same(0, exit_code)
    end)

    it("should not work when an unexisting plugin is being enabled along with an existing one", function()
      replace_conf_property("custom_plugins", {"key-auth", "wot-wat"})

      assert.error_matches(function()
        spec_helper.start_kong(SERVER_CONF)
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

      local _, exit_code = spec_helper.start_kong(SERVER_CONF)
      assert.are.same(0, exit_code)
    end)

    it("#ci should not work when a plugin is being used in the DB but it's not in the configuration", function()
      spec_helper.prepare_db()

      local cassandra = require "cassandra"
      local UUID = "d7dcf800-f155-417e-a282-b6189d7d901b"
      
      -- Load everything we need from the spec_helper
      local env = spec_helper.get_env(SERVER_CONF)
      local faker = env.faker
      local configuration = env.configuration
      local dao_factory = Factory("cassandra", configuration["cassandra"])

      local session, err = cassandra.spawn_session {
        shm = "cli_specs",
        keyspace = configuration["cassandra"].keyspace,
        contact_points = configuration["cassandra"].contact_points
      }
      assert.falsy(err)

      finally(function()    
        session:execute("DELETE FROM plugins WHERE id = "..UUID)
        session:shutdown()
      end)
      
      -- Insert API
      local api_t = faker:fake_entity("api")
      local api, err = dao_factory.apis:insert(api_t)
      assert.falsy(err)
      assert.truthy(api.id)

      -- Insert plugin
      local res, err = session:execute("INSERT INTO plugins(id, name, api_id, config) VALUES("..UUID..", 'custom-rate-limiting', "..api.id..", '{}')")
      assert.falsy(err)
      assert.truthy(res)

      replace_conf_property("custom_plugins", {})

      assert.error_matches(function()
        replace_conf_property("database", "cassandra")
        spec_helper.start_kong(SERVER_CONF)
      end, "You are using a plugin that has not been enabled in the configuration: custom-rate-limiting", nil, true)
    end)

  end)
  
end)
