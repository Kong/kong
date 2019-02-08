local helpers = require "spec.helpers"
local cjson   = require "cjson"
local enums   = require "kong.enterprise_edition.dao.enums"


for _, strategy in helpers.each_strategy('postgres') do
  describe("#flaky Developer status validation [#" .. strategy .. "]", function()
    local proxy_client
    local bp, dao
    local proxy_consumer, approved_developer, pending_developer
    local rejected_developer, revoked_developer, invited_developer
    local route1

    setup(function()
      bp, _, dao = helpers.get_db_utils(strategy)

      proxy_consumer = bp.consumers:insert {
        username = "proxy_consumer",
        type     = enums.CONSUMERS.TYPE.PROXY,
      }

      approved_developer = bp.consumers:insert {
        username = "approved_developer",
        type     = enums.CONSUMERS.TYPE.DEVELOPER,
        status   = enums.CONSUMERS.STATUS.APPROVED,
      }

      pending_developer = bp.consumers:insert {
        username = "pending_developer",
        type     = enums.CONSUMERS.TYPE.DEVELOPER,
        status   = enums.CONSUMERS.STATUS.PENDING,
      }

      rejected_developer = bp.consumers:insert {
        username = "rejected_developer",
        type     = enums.CONSUMERS.TYPE.DEVELOPER,
        status   = enums.CONSUMERS.STATUS.REJECTED,
      }

      revoked_developer = bp.consumers:insert {
        username = "revoked_developer",
        type     = enums.CONSUMERS.TYPE.DEVELOPER,
        status   = enums.CONSUMERS.STATUS.REVOKED,
      }

      invited_developer = bp.consumers:insert {
        username = "invited_developer",
        type     = enums.CONSUMERS.TYPE.DEVELOPER,
        status   = enums.CONSUMERS.STATUS.INVITED,
      }

      route1 = bp.routes:insert {
        hosts = { "basic-auth.com" },
      }

      bp.plugins:insert {
        name     = "basic-auth",
        route_id = route1.id,
      }

      assert(dao.basicauth_credentials:insert {
        username    = "proxy_consumer",
        password    = "kong",
        consumer_id = proxy_consumer.id,
      })

      assert(dao.basicauth_credentials:insert {
        username    = "approved_developer",
        password    = "kong",
        consumer_id = approved_developer.id,
      })

      assert(dao.basicauth_credentials:insert {
        username    = "pending_developer",
        password    = "kong",
        consumer_id = pending_developer.id,
      })

      assert(dao.basicauth_credentials:insert {
        username    = "rejected_developer",
        password    = "kong",
        consumer_id = rejected_developer.id,
      })

      assert(dao.basicauth_credentials:insert {
        username    = "revoked_developer",
        password    = "kong",
        consumer_id = revoked_developer.id,
      })

      assert(dao.basicauth_credentials:insert {
        username    = "invited_developer",
        password    = "kong",
        consumer_id = invited_developer.id,
      })

      assert(helpers.start_kong({
        database   = strategy,
        nginx_conf = "spec/fixtures/custom_nginx.template",
      }))

      proxy_client = helpers.proxy_client()
    end)


    teardown(function()
      if proxy_client then
        proxy_client:close()
      end

      helpers.stop_kong()
    end)

    describe("Proxy Consumer", function()
      it("succeeds with no status", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/request",
          headers = {
            ["Authorization"] = "Basic " .. ngx.encode_base64("proxy_consumer:kong"),
            ["Host"]          = "basic-auth.com"
          }
        })
        assert.res_status(200, res)
      end)
    end)

    describe("Developer Consumer", function()
      it("succeeds when consumer status is approved", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/request",
          headers = {
            ["Authorization"] = "Basic " .. ngx.encode_base64("approved_developer:kong"),
            ["Host"]          = "basic-auth.com"
          }
        })
        assert.res_status(200, res)
      end)

      it("returns 401 when consumer status is pending", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/request",
          headers = {
            ["Authorization"] = "Basic " .. ngx.encode_base64("pending_developer:kong"),
            ["Host"]          = "basic-auth.com"
          }
        })
        local body = assert.res_status(401, res)
        local json = cjson.decode(body)
        assert.same({ status = 1, label = "PENDING" }, json)
      end)

      it("returns 401 when consumer status is rejected", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/request",
          headers = {
            ["Authorization"] = "Basic " .. ngx.encode_base64("rejected_developer:kong"),
            ["Host"]          = "basic-auth.com"
          }
        })
        local body = assert.res_status(401, res)
        local json = cjson.decode(body)
        assert.same({ status = 2, label = "REJECTED" }, json)
      end)

      it("returns 401 when consumer status is revoked", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/request",
          headers = {
            ["Authorization"] = "Basic " .. ngx.encode_base64("revoked_developer:kong"),
            ["Host"]          = "basic-auth.com"
          }
        })
        local body = assert.res_status(401, res)
        local json = cjson.decode(body)
        assert.same({ status = 3, label = "REVOKED" }, json)
      end)

      it("returns 401 when consumer status is invited", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/request",
          headers = {
            ["Authorization"] = "Basic " .. ngx.encode_base64("invited_developer:kong"),
            ["Host"]          = "basic-auth.com"
          }
        })
        local body = assert.res_status(401, res)
        local json = cjson.decode(body)
        assert.same({ status = 4, label = "INVITED" }, json)
      end)
    end)
  end)
end
