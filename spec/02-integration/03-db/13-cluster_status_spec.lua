-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local helpers = require "spec.helpers"


for _, strategy in helpers.each_strategy() do
  describe("kong.db [#" .. strategy .. "]", function()
    local db, bp, cs

    lazy_setup(function()
      bp, db = helpers.get_db_utils(strategy, {
        "clustering_data_planes",
      })
    end)

    describe("Clustering DP status", function()

      before_each(function()
        cs = assert(bp.clustering_data_planes:insert())
      end)

      it("can update the row", function()
        local p, err = db.clustering_data_planes:update(cs, { config_hash = "a9a166c59873245db8f1a747ba9a80a7", })
        assert.is_truthy(p)
        assert.is_nil(err)
      end)
    end)

    describe("updates", function()
      it(":upsert()", function()
        local p, err = db.clustering_data_planes:upsert({ id = "eb51145a-aaaa-bbbb-cccc-22087fb081db", },
                                                 { config_hash = "a9a166c59873245db8f1a747ba9a80a7",
                                                   hostname = "localhost",
                                                   ip = "127.0.0.1",
                                                 })

        assert.is_truthy(p)
        assert.is_nil(err)
      end)

      it(":update()", function()
        -- this time update instead of insert
        local p, err = db.clustering_data_planes:update({ id = "eb51145a-aaaa-bbbb-cccc-22087fb081db", },
                                          { config_hash = "a9a166c59873245db8f1a747ba9a80a7", })
        assert.is_truthy(p)
        assert.is_nil(err)
      end)
    end)

    describe("labels", function()
      it(":upsert()", function()
        local p, err = db.clustering_data_planes:upsert({ id = "eb51145a-aaaa-bbbb-cccc-22087fb081db", },
                                                 { config_hash = "a9a166c59873245db8f1a747ba9a80a7",
                                                   hostname = "localhost",
                                                   ip = "127.0.0.1",
                                                   labels = {
                                                     deployment = "mycloud",
                                                     region = "us-east-1",
                                                   }
                                                 })

        assert.is_truthy(p)
        assert.is_nil(err)
      end)

      it(":update()", function()
        -- this time update instead of insert
        local p, err = db.clustering_data_planes:update({ id = "eb51145a-aaaa-bbbb-cccc-22087fb081db", },
                                          { config_hash = "a9a166c59873245db8f1a747ba9a80a7",
                                            labels = { deployment = "aws", region = "us-east-2" }
                                          })
        assert.is_truthy(p)
        assert.is_nil(err)
      end)
    end)
  end) -- kong.db [strategy]
end
