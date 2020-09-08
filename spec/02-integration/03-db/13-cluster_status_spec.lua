local helpers = require "spec.helpers"


for _, strategy in helpers.each_strategy() do
  describe("kong.db [#" .. strategy .. "]", function()
    local db, bp, cs

    lazy_setup(function()
      bp, db = helpers.get_db_utils(strategy, {
        "cluster_status",
      })
    end)

    describe("Plugins #plugins", function()

      before_each(function()
        cs = assert(bp.cluster_status:insert())
      end)

      it("can update the row", function()
        local p, err = db.cluster_status:update({ id = cs.id, }, { config_hash = "a9a166c59873245db8f1a747ba9a80a7", })
        assert.is_truthy(p)
        assert.is_nil(err)
      end)
    end)

    describe("updates", function()
      it(":upsert()", function()
        local p, err = db.cluster_status:upsert({ id = "eb51145a-aaaa-bbbb-cccc-22087fb081db", },
                                                 { config_hash = "a9a166c59873245db8f1a747ba9a80a7",
                                                   hostname = "localhost",
                                                   ip = "127.0.0.1",
                                                 })

        assert.is_truthy(p)
        assert.is_nil(err)
      end)

      it(":update()", function()
        -- this time update instead of insert
        local p, err = db.cluster_status:update({ id = "eb51145a-aaaa-bbbb-cccc-22087fb081db", },
                                          { config_hash = "a9a166c59873245db8f1a747ba9a80a7", })
        assert.is_truthy(p)
        assert.is_nil(err)
      end)
    end)
  end) -- kong.db [strategy]
end
