local cassandra_db = require "kong.dao.db.cassandra"

describe("cassandra_db", function()
  describe("extract_major()", function()
    it("extract major version digit", function()
      assert.equal("3", cassandra_db.extract_major("3.7"))
      assert.equal("3", cassandra_db.extract_major("3.7.12"))
      assert.equal("2", cassandra_db.extract_major("2.1.14"))
      assert.equal("2", cassandra_db.extract_major("2.10"))
      assert.equal("10", cassandra_db.extract_major("10.0"))
    end)
  end)

  describe("extract_major_minor()", function()
    it("extract major and minor version digits", function()
      assert.equal("3.7", cassandra_db.extract_major_minor("3.7"))
      assert.equal("3.7", cassandra_db.extract_major_minor("3.7.12"))
      assert.equal("2.1", cassandra_db.extract_major_minor("2.1.14"))
      assert.equal("2.10", cassandra_db.extract_major_minor("2.10"))
      assert.equal("10.0", cassandra_db.extract_major_minor("10.0"))
    end)
  end)

  describe("cluster_release_version()", function()
    it("extracts major release_version from available peers", function()
      local release_version = assert(cassandra_db.cluster_release_version {
        {
          host = "127.0.0.1",
          release_version = "3.7",
        },
        {
          host = "127.0.0.2",
          release_version = "3.7",
        },
        {
          host = "127.0.0.3",
          release_version = "3.1.2",
        }
      })
      assert.same({
        major       = "3",
        major_minor = "3.7",
      }, release_version)

      local release_version = assert(cassandra_db.cluster_release_version {
        {
          host = "127.0.0.1",
          release_version = "2.14",
        },
        {
          host = "127.0.0.2",
          release_version = "2.11.14",
        },
        {
          host = "127.0.0.3",
          release_version = "2.2.4",
        }
      })
      assert.same({
        major       = "2",
        major_minor = "2.14",
      }, release_version)
    end)
    it("errors with different major versions", function()
      local release_version, err = cassandra_db.cluster_release_version {
        {
          host = "127.0.0.1",
          release_version = "3.7",
        },
        {
          host = "127.0.0.2",
          release_version = "3.7",
        },
        {
          host = "127.0.0.3",
          release_version = "2.11.14",
        }
      }
      assert.is_nil(release_version)
      assert.equal("different major versions detected (only all of 2.x or 3.x supported): 127.0.0.1 (3.7) 127.0.0.2 (3.7) 127.0.0.3 (2.11.14)", err)
    end)
    it("errors if a peer is missing release_version", function()
      local release_version, err = cassandra_db.cluster_release_version {
        {
          host = "127.0.0.1",
          release_version = "3.7",
        },
        {
          host = "127.0.0.2"
        }
      }
      assert.is_nil(release_version)
      assert.equal("no release_version for peer 127.0.0.2", err)
    end)
  end)

  describe("get_coordinator()", function()
    it("returns an error if no coordinator has been set", function()
      local coordinator, err = cassandra_db:get_coordinator()
      assert.is_nil(coordinator)
      assert.equal("no coordinator has been set", err)
    end)
  end)
end)
