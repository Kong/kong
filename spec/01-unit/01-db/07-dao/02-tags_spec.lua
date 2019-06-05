local Tags = require("kong.db.dao.tags")
local Dao = require("kong.db.dao")
local Entity = require("kong.db.schema.entity")
local Errors = require("kong.db.errors")


describe("kong.db.dao.tags", function()
  local self

  lazy_setup(function()
    local schema = assert(Entity.new(require("kong.db.schema.entities.tags")))

    self = {
      schema = schema,
      errors = Errors.new(),
      db = {},
    }
  end)

  it("forbid insert/upsert/update/delete on tags entity", function()
    for _, op in ipairs({ "insert", "upsert", "update", "delete" }) do
      local row, err, err_t = Tags[op](self, { tags = "tag" })
      assert.is_nil(row)
      assert.equal('schema violation (tags: does not support insert/upsert/update/delete operations)', err)
      assert.is_not_nil(err_t)
    end
  end)

end)


describe("kong.db.dao with foreign_key", function()
  local dao, strategy

  lazy_setup(function()
    assert(Entity.new(require("kong.db.schema.entities.upstreams")))
    local schema = assert(Entity.new(require("kong.db.schema.entities.targets")))

    strategy = setmetatable({}, {__index = function() return function() end end})

    dao = Dao.new(nil, schema, strategy)
  end)

  it("each_for/page_for are not tag-enabled", function()
    local s = spy.on(strategy, 'page')
    local spage = spy.on(strategy, 'page_for_upstream')

    local _, err, _ = dao:each_for_upstream({ id = "7b0c42a0-e5f9-458e-9afd-6201a7879971" }, nil, { tags = { "foo" } })

    assert.is_nil(err)
    
    assert.spy(s).was_not_called()
    assert.spy(spage).was_called(1)

    _, err, _ = dao:page_for_upstream({ id = "7b0c42a0-e5f9-458e-9afd-6201a7879971" }, nil, nil, { tags = { "foo" } })

    assert.is_nil(err)

    assert.spy(s).was_not_called()
    assert.spy(spage).was_called(2)

  end)
end)