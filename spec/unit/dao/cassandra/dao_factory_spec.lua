local Factory = require "kong.dao.cassandra.factory"
local cassandra = require "cassandra"
local types = require "cassandra.types"

-- Test behavior specific to CassandraDAOFactory only.
local CassandraDAOFactory = require "kong.dao.cassandra.dao_factory"
local config = require "kong.tools.config_loader"

local DEFAULT_CONFIG = config.default_config()
local DEFAULT_CASSANDRA_CONFIG = DEFAULT_CONFIG.cassandra

describe("CassandraDAOfactory #dao #cass", function()
  describe("session options", function()
    local dao_properties
    before_each(function()
      dao_properties = DEFAULT_CASSANDRA_CONFIG
    end)
    it("should serialize default properties to create session_options", function()
      local CassandraDAOfactory = CassandraDAOFactory(dao_properties)
      assert.truthy(CassandraDAOfactory)
      local options = CassandraDAOfactory.session_options
      assert.truthy(options)
      assert.same({
        shm = "cassandra",
        prepared_shm = "cassandra_prepared",
        contact_points = dao_properties.contact_points,
        keyspace = dao_properties.keyspace,
        query_options = {
          consistency = types.consistencies.one,
          prepare = true
        },
        socket_options = {
          connect_timeout = 5000,
          read_timeout = 5000
        },
        ssl_options = {
          enabled = false,
          verify = false
        }
      }, options)
    end)
    it("should serialize some overriden properties to create session_options", function()
      dao_properties.contact_points = {"127.0.0.1:9042"}
      dao_properties.keyspace = "my_keyspace"

      local CassandraDAOfactory = CassandraDAOFactory(dao_properties)
      assert.truthy(CassandraDAOfactory)
      local options = CassandraDAOfactory.session_options
      assert.truthy(options)
      assert.same({
        shm = "cassandra",
        prepared_shm = "cassandra_prepared",
        contact_points = {"127.0.0.1:9042"},
        keyspace = "my_keyspace",
        query_options = {
          consistency = types.consistencies.one,
          prepare = true
        },
        socket_options = {
          connect_timeout = 5000,
          read_timeout = 5000
        },
        ssl_options = {
          enabled = false,
          verify = false
        }
      }, options)
    end)
    it("should accept authentication properties", function()
      dao_properties.username = "cassie"
      dao_properties.password = "cassiepwd"

      local factory = Factory(dao_properties)
      assert.truthy(factory)
      local options = factory:get_session_options()
      assert.truthy(options)
      assert.same({
        shm = "cassandra",
        prepared_shm = "cassandra_prepared",
        contact_points = {"127.0.0.1:9042"},
        keyspace = "kong_tests",
        query_options = {
          consistency = types.consistencies.one,
          prepare = true
        },
        socket_options = {
          connect_timeout = 5000,
          read_timeout = 5000
        },
        ssl_options = {
          enabled = false,
          verify = false
        },
        auth = cassandra.auth.PlainTextProvider("cassie", "cassiepwd")
      }, options)
    end)
    it("should accept SSL properties", function()
      dao_properties.contact_points = {"127.0.0.1:9042"}
      dao_properties.ssl.enabled = false
      dao_properties.ssl.verify = true

      local CassandraDAOfactory = CassandraDAOFactory(dao_properties)
      assert.truthy(CassandraDAOfactory)
      local options = CassandraDAOfactory.session_options
      assert.truthy(options)
      assert.same({
        shm = "cassandra",
        prepared_shm = "cassandra_prepared",
        contact_points = {"127.0.0.1:9042"},
        keyspace = "kong_tests",
        query_options = {
          consistency = types.consistencies.one,
          prepare = true
        },
        socket_options = {
          connect_timeout = 5000,
          read_timeout = 5000
        },
        ssl_options = {
          enabled = false,
          verify = true
        }
      }, options)

      -- TEST 2
      dao_properties.ssl.enabled = true
      CassandraDAOfactory = CassandraDAOFactory(dao_properties)
      assert.truthy(CassandraDAOfactory)
      local options = CassandraDAOfactory.session_options
      assert.truthy(options)
      assert.same({
        shm = "cassandra",
        prepared_shm = "cassandra_prepared",
        contact_points = {"127.0.0.1:9042"},
        keyspace = "kong_tests",
        query_options = {
          consistency = types.consistencies.one,
          prepare = true
        },
        socket_options = {
          connect_timeout = 5000,
          read_timeout = 5000
        },
        ssl_options = {
          enabled = true,
          verify = true
        }
      }, options)
    end)
  end)
end)
