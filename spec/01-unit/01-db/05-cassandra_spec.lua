local connector = require "kong.db.strategies.cassandra.connector"
local cassandra = require "cassandra"
local helpers = require "spec.helpers"


describe("kong.db [#cassandra] connector", function()
  describe(".new()", function()
    local test_conf = helpers.test_conf
    local test_conf_lb_policy = test_conf.cassandra_lb_policy
    local test_conf_local_datacenter = test_conf.cassandra_local_datacenter

    lazy_teardown(function()
      test_conf.cassandra_lb_policy = test_conf_lb_policy
      test_conf.cassandra_local_datacenter = test_conf_local_datacenter
    end)

    it("sets serial_consistency to serial if LB policy is not DCAware", function()
      for _, policy in ipairs({ "RoundRobin", "RequestRoundRobin" }) do
        test_conf.cassandra_lb_policy = policy
        local c = assert(connector.new(test_conf))
        assert.equal(cassandra.consistencies.serial, c.opts.serial_consistency)
      end
    end)

    it("sets serial_consistency to local_serial if LB policy is DCAware", function()
      test_conf.cassandra_local_datacenter = "dc1"

      for _, policy in ipairs({ "DCAwareRoundRobin", "RequestDCAwareRoundRobin" }) do
        test_conf.cassandra_lb_policy = policy
        local c = assert(connector.new(test_conf))
        assert.equal(cassandra.consistencies.local_serial, c.opts.serial_consistency)
      end
    end)
  end)

  describe(":infos()", function()
    it("returns infos db_ver always with two digit groups divided with dot (.)", function()
      local infos = connector.infos{ major_version = 2, major_minor_version = "2.10" }
      assert.same({
        db_desc  = "keyspace",
        db_ver   = "2.10",
        strategy = "Cassandra",
      }, infos)

      infos = connector.infos{ major_version = 2, major_minor_version = "2.10.1" }
      assert.same({
        db_desc  = "keyspace",
        db_ver   = "2.10",
        strategy = "Cassandra",
      }, infos)

      infos = connector.infos{ major_version = 3, major_minor_version = "3.7" }
      assert.same({
        db_desc  = "keyspace",
        db_ver   = "3.7",
        strategy = "Cassandra",
      }, infos)
    end)

    it("returns infos with db_ver as \"unknown\" when missing major_minor_version", function()
      local infos = connector.infos{ major_version = 2 }
      assert.same({
        db_desc  = "keyspace",
        db_ver   = "unknown",
        strategy = "Cassandra",
      }, infos)

      infos = connector.infos{ major_version = 3 }
      assert.same({
        db_desc  = "keyspace",
        db_ver   = "unknown",
        strategy = "Cassandra",
      }, infos)

      infos = connector.infos{}
      assert.same({
        db_desc  = "keyspace",
        db_ver   = "unknown",
        strategy = "Cassandra",
      }, infos)
    end)

    it("returns infos with db_ver as \"unknown\" when invalid major_minor_version", function()
      local infos = connector.infos{ major_version = 2, major_minor_version = "invalid" }
      assert.same({
        db_desc  = "keyspace",
        db_ver   = "unknown",
        strategy = "Cassandra",
      }, infos)

      infos = connector.infos{ major_version = 3, major_minor_version = "invalid" }
      assert.same({
        db_desc  = "keyspace",
        db_ver   = "unknown",
        strategy = "Cassandra",
      }, infos)

      infos = connector.infos{ major_minor_version = "invalid" }
      assert.same({
        db_desc  = "keyspace",
        db_ver   = "unknown",
        strategy = "Cassandra",
      }, infos)
    end)
  end)
end)
