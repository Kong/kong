local path = require "pl.path"
local utils = require "pl.utils"

describe("Credential loading", function()

  local username = "kong"
  local password = "gorilla"
  local x_username = "mashape"
  local x_password = "jason"
  local x_user_file = path.tmpname()
  local x_pass_file = path.tmpname()
  
  setup(function()
    utils.writefile(x_user_file, x_username)
    utils.writefile(x_pass_file, x_password)
  end)

  teardown(function()
    os.remove(x_user_file)
    os.remove(x_pass_file)
  end)

  describe("[postgres]", function()

    local pg

    setup(function()
      pg = require("kong.dao.db.postgres")
    end)

    it("credentials from config", function()
      local options = {
        pg_user           = username,
        pg_password       = password,
        pg_cred_from_file = false,
        pg_user_file      = x_user_file,
        pg_password_file  = x_pass_file,
      }
      local pgdb = pg.new(options)
      assert.equal(username, pgdb.query_options.user)
      assert.equal(password, pgdb.query_options.password)
    end)

    it("credentials from file", function()
      local options = {
        pg_user           = username,
        pg_password       = password,
        pg_cred_from_file = true,
        pg_user_file      = x_user_file,
        pg_password_file  = x_pass_file,
      }
      local pgdb = pg.new(options)
      assert.equal(x_username, pgdb.query_options.user)
      assert.equal(x_password, pgdb.query_options.password)
    end)

    it("credentials from non-existing files", function()
      local options = {
        pg_user           = username,
        pg_password       = password,
        pg_cred_from_file = true,
        pg_user_file      = x_user_file .. "x",
        pg_password_file  = x_pass_file,
      }
      assert.has.error(function()
        local pgdb = pg.new(options)
      end)

      local options = {
        pg_user           = username,
        pg_password       = password,
        pg_cred_from_file = true,
        pg_user_file      = x_user_file,
        pg_password_file  = x_pass_file .. "x",
      }
      assert.has.error(function()
        local pgdb = pg.new(options)
      end)
    end)

  end)

  describe("[cassandra]", function()

    local snapshot, s, cassandra, cassandra_dao

    setup(function()
      snapshot = assert:snapshot()
      cassandra = require("cassandra")
      cassandra_dao = require("kong.dao.db.cassandra")
      s = spy.on(cassandra.auth_providers, "plain_text")
    end)
  
    teardown(function()
      snapshot:revert()
    end)

    it("credentials from config", function()
      local options = {
        cassandra_username       = username,
        cassandra_password       = password,
        cassandra_cred_from_file = false,
        cassandra_username_file  = x_user_file,
        cassandra_password_file  = x_pass_file,
        cassandra_consistency    = "ONE",
      }
      local cdb = cassandra_dao.new(options)
      assert.spy(s).was.called.with(username, password)
    end)

    it("credentials from file", function()
      local options = {
        cassandra_username       = username,
        cassandra_password       = password,
        cassandra_cred_from_file = true,
        cassandra_username_file  = x_user_file,
        cassandra_password_file  = x_pass_file,
        cassandra_consistency    = "ONE",
      }
      local cdb = cassandra_dao.new(options)
      assert.spy(s).was.called.with(x_username, x_password)
    end)

    it("credentials from non-existing files", function()
      local options = {
        cassandra_username       = username,
        cassandra_password       = password,
        cassandra_cred_from_file = true,
        cassandra_username_file  = x_user_file .. "x",
        cassandra_password_file  = x_pass_file,
        cassandra_consistency    = "ONE",
      }
      assert.has.error(function()
        local cdb = cassandra_dao.new(options)
      end)

      local options = {
        cassandra_username       = username,
        cassandra_password       = password,
        cassandra_cred_from_file = true,
        cassandra_username_file  = x_user_file,
        cassandra_password_file  = x_pass_file .. "x",
        cassandra_consistency    = "ONE",
      }
      assert.has.error(function()
        local cdb = cassandra_dao.new(options)
      end)
    end)

  end)

end)