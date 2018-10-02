local helpers = require "spec.helpers"

for _, strategy in helpers.each_strategy() do
  describe("default portal_config initialization" .. strategy, function()
    local db
    local dao
    local client

    setup(function()
      _, db, dao = helpers.get_db_utils(strategy)
    end)

    teardown(function()
      helpers.stop_kong()
    end)

    describe("default portal config", function()
      it("is only created once", function()
        local we_res, we_err = dao.workspace_entities:find_all({
          workspace_name= "default",
          entity_type="portal_configs",
        })
        assert.equal(we_err, nil)

        helpers.stop_kong()

        assert(helpers.start_kong({
          database = strategy,
          portal_auth = "basic-auth",
        }))

        local pc_id = we_res[1].entity_id

        local pc_res, _ = dao.portal_configs:find({ id = pc_id })
        assert.equal(pc_res.id, pc_id)
      end)

      before_each(function()
        helpers.stop_kong()
        assert(db:truncate())

        assert(helpers.start_kong({
          database   = strategy,
          portal_auth = "basic-auth",
        }))

        client = assert(helpers.proxy_client())
      end)

      after_each(function()
        if client then
          client:close()
        end
      end)
    end)
  end)
end
