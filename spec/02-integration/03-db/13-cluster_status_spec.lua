local helpers = require "spec.helpers"


for _, strategy in helpers.each_strategy() do
  describe("kong.db [#" .. strategy .. "]", function()
    local db, bp, cs
    local global_plugin

    lazy_setup(function()
      bp, db = helpers.get_db_utils(strategy, {
        "cluster_status",
      })
    end)

    describe("Plugins #plugins", function()

      before_each(function()
        cs = bp.cluster_status:insert()
      end)

      it("can update the row", function()
        local p, _, err_t = db.cluster_status:update({ config_hash = "1234567890", })
        assert.is_truthy(p)
        assert.is_nil(err_t)
      end)
    end)

    describe(":upsert()", function()
      it("returns an error when upserting mismatched plugins", function()
        local p, _, err_t = db.cluster_status:upsert({ id = "eb51145a-aaaa-bbbb-cccc-22087fb081db", },
                                                     { config_hash = "1234567890", })

        assert.is_truthy(p)
        assert.is_nil(err_t)

        -- this time update instead of insert
        p, _, err_t = db.cluster_status:upsert({ id = "eb51145a-aaaa-bbbb-cccc-22087fb081db", },
                                                     { config_hash = "1234567890", })
        assert.is_truthy(p)
        assert.is_nil(err_t)
      end)
    end)
  end) -- kong.db [strategy]
end
