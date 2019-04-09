local helpers = require "spec.helpers"


for _, strategy in helpers.each_strategy() do
  describe("kong.dao [#" .. strategy .. "]", function()
    local dao

    setup(function()
      ngx.ctx.workspaces = nil
      dao = select(3, helpers.get_db_utils(strategy))
    end)

    teardown(function()
      dao:truncate_tables()
    end)

    describe("consumers", function()
      it("add null custom_id", function()

        local consumer_create, err, err_t = dao.consumers:insert {
          username = "bob",
          custom_id = ngx.null,
        }
        assert.is_nil(err_t)
        assert.is_nil(err)

        local _, err, err_t = dao.consumers:update({
          username = "foo",
          custom_id = ngx.null,
        }, {id = consumer_create.id})
        assert.is_nil(err_t)
        assert.is_nil(err)

        local rows, err, err_t = dao.consumers:find_all({
          username = "foo",
        })
        assert.is_nil(err_t)
        assert.is_nil(err)
        assert.equal("foo", rows[1].username)
        assert.is_nil(rows[1].custom_id)
      end)
    end)
  end)
end
