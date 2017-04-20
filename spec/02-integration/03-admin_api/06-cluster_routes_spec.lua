local helpers = require "spec.helpers"
local cjson = require "cjson"

describe("Admin API", function()
  local client
  setup(function()
    assert(helpers.start_kong())
  end)
  teardown(function()
    if client then client:close() end
    helpers.stop_kong()
  end)
  before_each(function()
    client = helpers.admin_client()
  end)
  after_each(function()
    if client then client:close() end
  end)

  describe("/cluster", function()
    describe("GET", function()
      it("retrieves the members list", function()
        -- old test converted
        --ngx.sleep(2) -- Let's wait for serf to register the node
        local res = assert(client:send {
          method = "GET",
          path = "/cluster"
        })
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.equal(1, #json.data)
        assert.equal(1, json.total)

        local member = json.data[1]
        assert.is_string(member.address)
        assert.is_string(member.name)
        assert.equal("alive", member.status)
      end)
    end)

    describe("DELETE", function()
      -- old test converted
      local log_path = helpers.path.join(helpers.test_conf.prefix, "serf_cluster_tests.log")
      local pid_path = helpers.path.join(helpers.test_conf.prefix, "serf_cluster_tests.pid")

      setup(function()
        local pl_utils = require "pl.utils"
        local kill = require "kong.cmd.utils.kill"
        local cmd = string.format("nohup %s agent -rpc-addr=127.0.0.1:20000 "
                                .."-bind=127.0.0.1:20001 -node=newnode > "
                                .."%s 2>&1 & echo $! > %s",
                                helpers.test_conf.serf_path, log_path, pid_path)
        assert(pl_utils.execute(cmd))

        local tstart = ngx.time()
        local texp, started = tstart + 2 -- 2s timeout
        repeat
          ngx.sleep(0.2)
          started = kill.is_running(pid_path)
        until started or ngx.time() >= texp
        assert(started, "Serf agent start: timeout")
      end)

      teardown(function()
        helpers.execute(string.format("kill $(cat %s)", pid_path))
        helpers.file.delete(log_path)
        helpers.file.delete(pid_path)
      end)

      it("force-leaves a node", function()
        -- old test converted
        local cmd = string.format("%s join -rpc-addr=%s 127.0.0.1:20001",
                                  helpers.test_conf.serf_path,
                                  helpers.test_conf.cluster_listen_rpc)
        assert(helpers.execute(cmd))

        local res = assert(client:send {
          method = "GET",
          path = "/cluster"
        })
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.equal(2, #json.data)
        assert.equal(2, json.total)
        assert.equal("alive", json.data[1].status)
        assert.equal("alive", json.data[2].status)

        res = assert(client:send {
          method = "DELETE",
          path = "/cluster",
          body = "name=newnode", -- why not in URI??
          headers = {["Content-Type"] = "application/x-www-form-urlencoded"}
        })
        assert.res_status(200, res) -- why not 204??

        helpers.wait_until(function()
          res = assert(client:send {
            method = "GET",
            path = "/cluster"
          })
          local body = assert.res_status(200, res)
          local json = cjson.decode(body)
          assert.equal(2, #json.data)
          assert.equal(2, json.total)

          local alive, leaving
          for k, v in ipairs(json.data) do
            if v.address == "127.0.0.1:20001" then
              leaving = v
            else
              alive = v
            end
          end

          assert.equal("alive", alive.status)
          return leaving.status == "leaving"
        end, 10)
      end)
    end)
  end)

  describe("/cluster/events", function()
    describe("POST", function()
      it("fails with an invalid event", function()
        local res = assert(client:send {
          method = "POST",
          path = "/cluster/events",
          body = {},
          headers = {["Content-Type"] = "application/json"}
        })
        assert.res_status(400, res)
      end)
      it("posts a new event", function()
        local res = assert(client:send {
          method = "POST",
          path = "/cluster/events",
          body = { type = "hello" },
          headers = {["Content-Type"] = "application/json"}
        })
        assert.res_status(200, res)
      end)
    end)
  end)
end)
