local CassandraFactory = require "kong.dao.cassandra.factory"
local spec_helper = require "spec.spec_helpers"

local env = spec_helper.get_env() -- test environment
local configuration = env.configuration
configuration.cassandra = configuration.databases_available[configuration.database].properties

describe(":prepare()", function()

  it("should return an error if cannot connect to Cassandra", function()
    local new_factory = CassandraFactory({ hosts = "127.0.0.1",
                                           port = 45678,
                                           timeout = 1000,
                                           keyspace = configuration.cassandra.keyspace
    })

    local err = new_factory:prepare()
    assert.truthy(err)
    assert.True(err.database)
    assert.are.same("Cassandra error: connection refused", err.message)
  end)

end)
