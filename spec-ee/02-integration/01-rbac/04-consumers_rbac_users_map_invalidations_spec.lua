local helpers = require "spec.helpers"
local enums = require "kong.enterprise_edition.dao.enums"
local ee_helpers = require "spec-ee.helpers"
local singletons = require "kong.singletons"


local POLL_INTERVAL = 0.3

local function cache_key(user)
  return singletons.dao.consumers_rbac_users_map:cache_key(user.id)
end


for _, strategy in helpers.each_strategy() do
  describe("#flaky consumers_rbac_users_mapping invalidations #" .. strategy, function()
    local bp
    local db
    local dao

    local admin_client
    local consumer
    local user
    local superuser
    local headers = {}

    setup(function()
      bp, db, dao = helpers.get_db_utils(strategy)

      consumer = assert(bp.consumers:insert {
        username = "hawk",
        type = enums.CONSUMERS.TYPE.ADMIN,
        -- status = enums.CONSUMERS.STATUS.APPROVED,
      })

      assert(bp.basicauth_credentials:insert {
        username    = "hawk",
        password    = "kong",
        consumer =  { id = consumer.id },
      })
      headers["Authorization"] = "Basic " .. ngx.encode_base64("hawk:kong")

      user = assert(dao.rbac_users:insert {
        name = "hawk",
        user_token = "tawken",
        enabled = true,
      })
      headers["Kong-Admin-User"] = user.name

      assert(db.consumers_rbac_users_map:insert {
        consumer_id = consumer.id,
        user_id = user.id,
      })

      -- make hawk super
      local _, super_role = ee_helpers.register_rbac_resources(dao)
      assert(db.rbac_user_roles:insert({
        user_id = user.id,
        role_id = super_role.role_id,
      }))

      superuser = assert(db.rbac_users:insert {
        name = "dale",
        user_token = "coop",
        enabled = true,
      })
      assert(db.rbac_user_roles:insert({
        user_id = superuser.id,
        role_id = super_role.role_id,
      }))

      local db_update_propagation = strategy == "cassandra" and 3 or 0

      assert(helpers.start_kong {
        admin_gui_auth        = "basic-auth",
        enforce_rbac          = "on",
        log_level             = "debug",
        database              = strategy,
        db_update_frequency   = POLL_INTERVAL,
        db_update_propagation = db_update_propagation,
        nginx_conf            = "spec/fixtures/custom_nginx.template",
      })

      admin_client = assert(helpers.admin_client())
    end)

    teardown(function()
      helpers.stop_kong()
    end)

    before_each(function()
      admin_client = helpers.admin_client()
    end)

    after_each(function()
      if admin_client then
        admin_client:close()
      end
    end)


    describe("consumers_rbac_users_map", function()
      it("caches", function()
        -- issue a request that populates the consumers_rbac_users_map cache
        local res = assert(admin_client:send {
          method  = "GET",
          path    = "/services",
          headers = headers
        })
        assert.res_status(200, res)

        -- check the cache
        local cache_res = assert(admin_client:send {
          method = "GET",
          path = "/cache/" .. cache_key(user),
          headers = headers
        })

        assert.res_status(200, cache_res)
      end)

      it("invalidates consumer rbac user map cache when admin is deleted",
        function()
          local admin = ee_helpers.create_admin("gruce@konghq.com", nil, 0, bp, dao)

          local res = assert(admin_client:send {
            method = "DELETE",
            path   = "/admins/" .. admin.id,
            headers = {
              ["Kong-Admin-Token"] = "letmein"
            }
          })
          assert.res_status(204, res)

          helpers.wait_until(function()
            local res = assert(admin_client:send {
              method = "GET",
              path   = "/cache/" .. cache_key(admin.rbac_user.id),
              body   = {},
              headers = {
                ["Kong-Admin-Token"] = "letmein"
              }
            })
            res:read_body()
            return res.status == 404
        end)
      end)
    end)
  end)
end
