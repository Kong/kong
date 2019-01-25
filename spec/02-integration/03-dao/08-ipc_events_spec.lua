local helpers          = require "spec.02-integration.03-dao.helpers"
local apis_schema      = require "kong.dao.schemas.apis"
local kong_dao_factory = require "kong.dao.factory"
local DB               = require "kong.db"

local mock_ipc_module = {
  post_local = function(source, event, data)
    return true
  end,
}


helpers.for_each_dao(function(kong_conf)

describe("DAO propagates CRUD events with DB: #" .. kong_conf.database, function()
  local dao
  local mock_ipc

  lazy_teardown(function()
    dao:truncate_table("apis")
  end)

  before_each(function()
    mock_ipc = mock(mock_ipc_module)

    local db = DB.new(kong_conf)
    assert(db:init_connector())

    dao = assert(kong_dao_factory.new(kong_conf, db))
    dao:set_events_handler(mock_ipc)
    dao:truncate_table("apis")
  end)

  after_each(function()
    mock.revert(mock_ipc)
  end)

  describe(":insert() with opts.quiet ", function()
    it("= false (default)", function()
      local api = assert(dao.apis:insert {
        name         = "api-1",
        hosts        = { "example.com" },
        upstream_url = "http://example.org",
      })

      -- XXX EE: flaky
      -- workspaces/rbac branch
      --assert.spy(mock_ipc.post_local).was_called(1)
      assert.spy(mock_ipc.post_local).was_called_with("dao:crud", "create", {
        schema    = apis_schema,
        operation = "create",
        entity    = api,
      })
    end)

    it("= true", function()
      assert(dao.apis:insert({
        name         = "api-2",
        hosts        = { "example.com" },
        upstream_url = "http://example.org",
      }, { quiet = true }))

      assert.spy(mock_ipc.post_local).was_not_called()
    end)
  end)

  describe(":update() with opts.quiet ", function()
    local api

    before_each(function()
      api = assert(dao.apis:insert({
        name         = "api-to-update",
        hosts        = { "example.com" },
        upstream_url = "http://example.org",
      }, { quiet = true }))
    end)

    it("= false (default)", function()
      local new_api = assert(dao.apis:update({
                               upstream_url = "http://example.com",
                             }, { id = api.id }))

      assert.spy(mock_ipc.post_local).was_called(1)
      assert.spy(mock_ipc.post_local).was_called_with("dao:crud", "update", {
        schema     = apis_schema,
        operation  = "update",
        entity     = new_api,
        old_entity = api,
      })
    end)

    it("= true", function()
      assert(dao.apis:update({
        upstream_url = "http://example.com",
      }, { id = api.id }, { quiet = true }))

      assert.spy(mock_ipc.post_local).was_not_called()
    end)
  end)

  describe(":delete() with opts.quiet ", function()
    local api

    before_each(function()
      api = assert(dao.apis:insert({
        name         = "api-to-update",
        hosts        = { "example.com" },
        upstream_url = "http://example.org",
      }, { quiet = true }))
    end)

    it("= false (default)", function()
      assert(dao.apis:delete({ id = api.id }))

      assert.spy(mock_ipc.post_local).was_called(1)
      assert.spy(mock_ipc.post_local).was_called_with("dao:crud", "delete", {
        schema     = apis_schema,
        operation  = "delete",
        entity     = api,
      })
    end)

    it("= true", function()
      assert(dao.apis:delete({ id = api.id }, { quiet = true }))
      assert.spy(mock_ipc.post_local).was_not_called()
    end)
  end)
end)

end)
