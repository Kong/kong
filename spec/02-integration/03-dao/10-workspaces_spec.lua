local workspaces = require "kong.workspaces"
local DAOFactory  = require "kong.dao.factory"
local helpers = require "spec.helpers"
local conf_loader = require "kong.conf_loader"

describe("apis have associated ws when", function()
  local dao,client
  setup(function()
    local conf = assert(
        conf_loader(helpers.test_conf_path, {database = "postgres"}))

    dao = assert(DAOFactory.new(conf))

    dao:truncate_tables()
    helpers.run_migrations(dao)
    assert(helpers.start_kong({database = "postgres"}))
    client = assert(helpers.admin_client())
  end)

  teardown(function()
    if client then
      client:close()
    end
    helpers.stop_kong(nil, true)
  end)

  it("is created", function()
    local ws_foo = dao.workspaces:insert({name = "foo"})

    ngx.ctx.workspaces = { ws_foo }
    local api1 = dao.apis:insert({
     name = "api1",
     hosts = "test1",
     upstream_url = "http://example.com",
    })

    local res = dao.apis:find_all({name = "api1"})
    assert.equal(1, #res)


    -- At the dao level only the core entity is created and the
    -- relations are created in the crud helpers
    -- TODO: move managing of workspace_entities to dao

    -- res = dao.workspace_entities:find_all({
    --   entity_id = api1.id,
    --   workspace_id = ws_foo.id
    -- })
    -- assert.equal(1, #res)
  end)

  -- it("is deleted", function()
  --   dao.workspaces:insert({name = "foo"})
  --   ngx.ctx.workspace = "foo"
  --   dao.apis:insert({
  --    name = "api1",
  --    hosts = "test1",
  --    upstream_url = "http://example.com",
  --   })
  --   local id = dao.apis:find_all({name = "api1"})[1].id
  --   local res = dao.apis:delete({id = id})
  --   assert.equal(0, #res)
  -- end)
end)
