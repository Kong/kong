local helpers = require "spec.helpers"


local ADMIN_HEADERS = {
  ["Content-Type"] = "application/json",
}


local function make_requests(proxy_client, suffix)
  local res = proxy_client:get("/", {
    query = {
      reference = "{vault://secrets/test}"
    }
  })
  assert.response(res).has.status(200)
  local json = assert.response(res).has.jsonbody()
  assert.same({
    prefix = "prefix",
    suffix = suffix,
    resource = "test",
  }, json)

  local res = proxy_client:get("/", {
    query = {
      reference = "{vault://secrets/test?prefix=prefix-new}"
    }
  })
  assert.response(res).has.status(200)
  local json = assert.response(res).has.jsonbody()
  assert.same({
    prefix = "prefix-new",
    suffix = suffix,
    resource = "test",
  }, json)

  local res = proxy_client:get("/", {
    query = {
      reference = "{vault://secrets/test}"
    }
  })
  assert.response(res).has.status(200)
  local json = assert.response(res).has.jsonbody()
  assert.same({
    prefix = "prefix",
    suffix = suffix,
    resource = "test",
  }, json)

  local res = proxy_client:get("/", {
    query = {
      reference = "{vault://secrets/test#1}"
    }
  })
  assert.response(res).has.status(200)
  local json = assert.response(res).has.jsonbody()
  assert.same({
    prefix = "prefix",
    suffix = suffix,
    resource = "test",
    version = 1,
  }, json)
end


for _, strategy in helpers.each_strategy({ "postgres" }) do
  describe("Vault configuration #" .. strategy, function()
    local admin_client
    local proxy_client

    lazy_setup(function()
      local bp = helpers.get_db_utils(strategy, { "vaults" }, { "secret-response" }, { "echo" })

      local route = bp.routes:insert {
        paths = { "/" },
      }

      bp.plugins:insert {
        name    = "secret-response",
        route   = { id = route.id },
      }

      assert(helpers.start_kong {
        database = strategy,
        prefix = helpers.test_conf.prefix,
        nginx_conf = "spec/fixtures/custom_nginx.template",
        plugins = "secret-response",
        vaults = "echo",
      })
    end)

    before_each(function()
      admin_client = assert(helpers.admin_client())
      proxy_client = assert(helpers.proxy_client())
    end)

    after_each(function()
      if admin_client then
        admin_client:close()
      end
      if proxy_client then
        proxy_client:close()
      end
    end)

    lazy_teardown(function()
      helpers.stop_kong()
    end)

    it("is not sticky (caches are properly cleared / new cache keys properly generated) ", function()
      -- Create Vault:
      local res = admin_client:put("/vaults/secrets", {
        body = {
          name = "echo",
          config = {
            prefix = "prefix",
            suffix = "suffix",
          },
        },
        headers = ADMIN_HEADERS,
      })
      assert.response(res).has.status(200)

      assert.eventually(function()
        -- Check Output:
        make_requests(proxy_client, "suffix")
      end).has_no_error("The vault configuration is not sticky")

      -- Patch Vault:
      local res = admin_client:patch("/vaults/secrets", {
        body = {
          config = {
            suffix = "suffix-new",
          },
        },
        headers = ADMIN_HEADERS,
      })
      assert.response(res).has.status(200)

      assert.eventually(function()
        -- Check Output:
        make_requests(proxy_client, "suffix-new")
      end).has_no_error("The vault configuration is not sticky")
    end)
  end)
end
