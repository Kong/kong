local helpers = require "spec.helpers"


for _, strategy in helpers.each_strategy() do
  describe("kong.db [#" .. strategy .. "]", function()
    local db

    setup(function()
      ngx.ctx.workspaces = nil
      db = select(2, helpers.get_db_utils(strategy))
    end)

    teardown(function()
      db:truncate()
    end)

    describe("consumers", function()
      it("add null custom_id", function()

        local consumer_create, err, err_t = db.consumers:insert {
          username = "bob",
          custom_id = ngx.null,
        }
        assert.is_nil(err_t)
        assert.is_nil(err)

        local _, err, err_t = db.consumers:update(
          {id = consumer_create.id},
          {
          username = "foo",
          custom_id = ngx.null
        })
        assert.is_nil(err_t)
        assert.is_nil(err)

        local row, err, err_t = db.consumers:select_by_username("foo")
        assert.is_nil(err_t)
        assert.is_nil(err)
        assert.equal("foo", row.username)
        assert.is_nil(row.custom_id)
      end)
    end)
  end)
end
