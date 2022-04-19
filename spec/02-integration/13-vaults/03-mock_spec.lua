local helpers = require "spec.helpers"
local cjson = require "cjson"
local meta = require "kong.meta"


local exists = helpers.path.exists
local join = helpers.path.join


local function get_kong_workers()
  local workers
  helpers.wait_until(function()
    local pok, admin_client = pcall(helpers.admin_client)
    if not pok then
      return false
    end
    local res = admin_client:send {
      method = "GET",
      path = "/",
    }
    if not res or res.status ~= 200 then
      return false
    end
    local body = assert.res_status(200, res)
    local json = cjson.decode(body)

    admin_client:close()
    workers = json.pids.workers
    return true
  end, 10)
  return workers
end


local function wait_until_no_common_workers(workers, expected_total, strategy)
  if strategy == "cassandra" then
    ngx.sleep(0.5)
  end
  helpers.wait_until(function()
    local pok, admin_client = pcall(helpers.admin_client)
    if not pok then
      return false
    end
    local res = assert(admin_client:send {
      method = "GET",
      path = "/",
    })
    assert.res_status(200, res)
    local json = cjson.decode(assert.res_status(200, res))
    admin_client:close()

    local new_workers = json.pids.workers
    local total = 0
    local common = 0
    if new_workers then
      for _, v in ipairs(new_workers) do
        total = total + 1
        for _, v_old in ipairs(workers) do
          if v == v_old then
            common = common + 1
            break
          end
        end
      end
    end
    return common == 0 and total == (expected_total or total)
  end)
end


for _, strategy in helpers.each_strategy() do
  describe("Mock Vault #" .. strategy, function()
    local client
    lazy_setup(function()
      helpers.setenv("ADMIN_LISTEN", "127.0.0.1:9001")
      helpers.setenv("KONG_LUA_PATH_OVERRIDE", "./spec/fixtures/custom_vaults/?.lua;./spec/fixtures/custom_vaults/?/init.lua;;")
      helpers.get_db_utils(strategy, {
        "vaults_beta",
      },
      nil, {
        "env",
        "mock"
      })

      assert(helpers.start_kong {
        database = strategy,
        prefix = helpers.test_conf.prefix,
        nginx_conf = "spec/fixtures/custom_nginx.template",
        admin_listen = "{vault://mock/admin-listen}",
        vaults = "env, mock",
      })
    end)

    lazy_teardown(function()
      helpers.stop_kong()
      helpers.unsetenv("KONG_LUA_PATH_OVERRIDE")
      helpers.unsetenv("ADMIN_LISTEN")
    end)

    after_each(function()
      if client then
        client:close()
      end
    end)

    describe("Kong Start", function()
      before_each(function()
        client = assert(helpers.admin_client(10000))
      end)

      it("can use co-sockets and resolved referenced are passed to Kong server", function()
        local res = client:get("/")
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.equal(meta._VERSION, json.version)
        assert.falsy(exists(join(helpers.test_conf.prefix, ".kong_process_secrets")))
      end)
    end)

    describe("Kong Reload", function()
      it("can use co-sockets and resolved referenced are passed to Kong server", function()
        local workers = get_kong_workers()

        assert(helpers.kong_exec("reload --conf " .. helpers.test_conf_path ..
                                 " --nginx-conf spec/fixtures/custom_nginx.template"))

        wait_until_no_common_workers(workers, 1)

        assert.falsy(exists(join(helpers.test_conf.prefix, ".kong_process_secrets")))

        local res = client:get("/")
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.equal(meta._VERSION, json.version)
      end)
    end)
  end)
end
