local helpers = require "spec.helpers"
local cache = require "kong.tools.database_cache"
local pl_stringx = require "pl.stringx"
local pl_tablex = require "pl.tablex"
local cjson = require "cjson"

local function exec(args, env)
  args = args or ""
  env = env or {}

  local env_vars = ""
  for k, v in pairs(env) do
    env_vars = string.format("%s KONG_%s=%s", env_vars, k:upper(), v)
  end
  return helpers.execute(env_vars.." "..helpers.bin_path.." "..args)
end

local NODES = {
  servroot1 = {
    prefix = "servroot1",
    proxy_listen = "127.0.0.1:9000",
    proxy_listen_ssl = "127.0.0.1:9443",
    admin_listen = "0.0.0.0:9001",
    cluster_listen = "0.0.0.0:9946",
    cluster_listen_rpc = "0.0.0.0:9373"
  },
  servroot2 = {
    prefix = "servroot2",
    proxy_listen = "127.0.0.1:10000",
    proxy_listen_ssl = "127.0.0.1:10443",
    admin_listen = "0.0.0.0:10001",
    cluster_listen = "0.0.0.0:10946",
    cluster_listen_rpc = "0.0.0.0:10373"
  },
  servroot3 = {
    prefix = "servroot3",
    proxy_listen = "127.0.0.1:20000",
    proxy_listen_ssl = "127.0.0.1:20443",
    admin_listen = "0.0.0.0:20001",
    cluster_listen = "0.0.0.0:20946",
    cluster_listen_rpc = "0.0.0.0:20373"
  }
}

describe("Cluster", function()
  before_each(function()
    helpers.kill_all()
    helpers.dao:truncate_tables()
  end)
  after_each(function()
    helpers.kill_all()
    for k, v in pairs(NODES) do
      helpers.clean_prefix(k)
    end
  end)

  describe("Nodes", function()
    it("should register the node on startup", function()
      assert(exec("start --conf "..helpers.test_conf_path, NODES.servroot1))

      -- Wait for node to be registered
      helpers.wait_until(function()
        return helpers.dao.nodes:count() == 1
      end)

      local node = helpers.dao.nodes:find_all()[1]
      assert.is_number(node.created_at)
      assert.is_string(node.name)
      assert.is_string(node.cluster_listening_address)

      local api_client = assert(helpers.http_client("127.0.0.1", pl_stringx.split(NODES.servroot1.admin_listen, ":")[2]))
      local res = assert(api_client:send {
        method = "GET",
        path = "/cluster/",
        headers = {}
      })
      local body = cjson.decode(assert.res_status(200, res))
      assert.equal(1, body.total)
      assert.equal(node.name, body.data[1].name)
      assert.equal(node.cluster_listening_address, body.data[1].address)
      assert.equal("alive", body.data[1].status)
    end)

    it("should register the node on startup with the advertised address", function()
      local conf = pl_tablex.deepcopy(NODES.servroot1)
      conf.cluster_advertise = "5.5.5.5:1234"

      assert(exec("start --conf "..helpers.test_conf_path, conf))

      -- Wait for node to be registered
      helpers.wait_until(function()
        return helpers.dao.nodes:count() == 1
      end)

      local node = helpers.dao.nodes:find_all()[1]
      assert.is_number(node.created_at)
      assert.is_string(node.name)
      assert.equal("5.5.5.5:1234", node.cluster_listening_address)

      local api_client = assert(helpers.http_client("127.0.0.1", pl_stringx.split(NODES.servroot1.admin_listen, ":")[2]))
      local res = assert(api_client:send {
        method = "GET",
        path = "/cluster/",
        headers = {}
      })
      local body = cjson.decode(assert.res_status(200, res))
      assert.equal(1, body.total)
      assert.equal(node.name, body.data[1].name)
      assert.equal(node.cluster_listening_address, body.data[1].address)
      assert.equal("alive", body.data[1].status)
    end)
  end)

  describe("Auto-join", function()
    it("should register the second node on startup and auto-join sequentially", function()
      assert(exec("start --conf "..helpers.test_conf_path, NODES.servroot1))
      -- Wait for first node to be registered
      helpers.wait_until(function()
        return helpers.dao.nodes:count() == 1
      end)

      assert(exec("start --conf "..helpers.test_conf_path, NODES.servroot2))
      -- Wait for second node to be registered
      helpers.wait_until(function()
        return helpers.dao.nodes:count() == 2
      end)

      local nodes = helpers.dao.nodes:find_all()
      assert.is_number(nodes[1].created_at)
      assert.is_string(nodes[1].name)
      assert.is_string(nodes[1].cluster_listening_address)
      assert.is_number(nodes[2].created_at)
      assert.is_string(nodes[2].name)
      assert.is_string(nodes[2].cluster_listening_address)

      -- Wait for nodes to be registered in Serf in both nodes
      for _, v in ipairs({NODES.servroot1, NODES.servroot2}) do
        local api_client = assert(helpers.http_client("127.0.0.1", pl_stringx.split(v.admin_listen, ":")[2]))
        helpers.wait_until(function()
          local res = assert(api_client:send {
            method = "GET",
            path = "/cluster/",
            headers = {}
          })
          local body = cjson.decode(assert.res_status(200, res))
          return body.total == 2
        end, 3)
      end
    end)

    it("should register the second node on startup and auto-join asyncronously", function()
      assert(exec("start --conf "..helpers.test_conf_path, NODES.servroot1))
      assert(exec("start --conf "..helpers.test_conf_path, NODES.servroot2))
      assert(exec("start --conf "..helpers.test_conf_path, NODES.servroot3))

      -- We need to wait a few seconds for the async job to kick in and join all the nodes together
      helpers.wait_until(function()
        local ok, _, stdout = helpers.execute("serf members -format=json -rpc-addr="..NODES.servroot1.cluster_listen_rpc)
        assert.True(ok)
        return #cjson.decode(stdout).members == 3
      end, 5)

      -- Wait for nodes to be registered in Serf in both nodes
      for _, v in ipairs({NODES.servroot1, NODES.servroot2, NODES.servroot3}) do
        local api_client = assert(helpers.http_client("127.0.0.1", pl_stringx.split(v.admin_listen, ":")[2]))
        helpers.wait_until(function()
          local res = assert(api_client:send {
            method = "GET",
            path = "/cluster/",
            headers = {}
          })
          local body = cjson.decode(assert.res_status(200, res))
          return body.total == 3
        end, 3)
      end
    end)
  end)

  describe("Cache purges", function()
    it("must purge cache on all nodes on member-join", function()
      assert(exec("start --conf "..helpers.test_conf_path, NODES.servroot1))
      -- Wait for first node to be registered
      helpers.wait_until(function()
        return helpers.dao.nodes:count() == 1
      end)

      -- Adding an API
      local api_client = assert(helpers.http_client("127.0.0.1", pl_stringx.split(NODES.servroot1.admin_listen, ":")[2]))
      local res = assert(api_client:send {
        method = "POST",
        path = "/apis/",
        headers = {
          ["Content-Type"] = "application/json"
        },
        body = {
          request_host = "test.com",
          upstream_url = "http://mockbin.org"
        }
      })
      assert.res_status(201, res)

      ngx.sleep(5) -- Wait for invalidation of API creation to propagate

      -- Populate the cache
      local client = assert(helpers.http_client("127.0.0.1", pl_stringx.split(NODES.servroot1.proxy_listen, ":")[2]))
      local res = assert(client:send {
        method = "GET",
        path = "/status/200/",
        headers = {
          ["Host"] = "test.com"
        }
      })
      assert.res_status(200, res)

      -- Checking the element in the cache
      local res = assert(api_client:send {
        method = "GET",
        path = "/cache/"..cache.all_apis_by_dict_key(),
        headers = {}
      })
      local body = cjson.decode(assert.res_status(200, res))
      assert.equal(1, pl_tablex.size(body.by_dns))
      assert.is_table(body.by_dns["test.com"])

      -- Starting second node
      assert(exec("start --conf "..helpers.test_conf_path, NODES.servroot2))
      -- Wait for the second node to be registered
      helpers.wait_until(function()
        return helpers.dao.nodes:count() == 2
      end)

      -- The cache on the first node should be invalidated, and the second node has no cache either because it was never invoked
      for _, v in ipairs({NODES.servroot1, NODES.servroot2}) do
        local api_client = assert(helpers.http_client("127.0.0.1", pl_stringx.split(v.admin_listen, ":")[2]))
        helpers.wait_until(function()
          local res = assert(api_client:send {
            method = "GET",
            path = "/cache/"..cache.all_apis_by_dict_key(),
            headers = {}
          })
          res:read_body()
          return res.status == 404
        end)
      end
    end)

    it("must purge cache on all nodes when a failed serf starts again (member-join event - simulation of a crash in a 3-node setup)", function()
      assert(exec("start --conf "..helpers.test_conf_path, NODES.servroot1))
      assert(exec("start --conf "..helpers.test_conf_path, NODES.servroot2))
      assert(exec("start --conf "..helpers.test_conf_path, NODES.servroot3))

      local api_client = assert(helpers.http_client("127.0.0.1", pl_stringx.split(NODES.servroot1.admin_listen, ":")[2]))
      helpers.wait_until(function()
        local res = assert(api_client:send {
          method = "GET",
          path = "/cluster/",
          headers = {}
        })
        local body = cjson.decode(assert.res_status(200, res))
        return body.total == 3
      end, 5)

      -- Now we have three nodes connected to each other, let's create and consume an API
      -- Adding an API
      local api_client = assert(helpers.http_client("127.0.0.1", pl_stringx.split(NODES.servroot1.admin_listen, ":")[2]))
      local res = assert(api_client:send {
        method = "POST",
        path = "/apis/",
        headers = {
          ["Content-Type"] = "application/json"
        },
        body = {
          request_host = "test.com",
          upstream_url = "http://mockbin.org"
        }
      })
      assert.res_status(201, res)

      ngx.sleep(5) -- Wait for invalidation of API creation to propagate

      -- Populate the cache on every node
      for _, v in ipairs({NODES.servroot1, NODES.servroot2, NODES.servroot3}) do
        local client = assert(helpers.http_client("127.0.0.1", pl_stringx.split(v.proxy_listen, ":")[2]))
        local res = assert(client:send {
          method = "GET",
          path = "/status/200",
          headers = {
            ["Host"] = "test.com"
          }
        })
        assert.res_status(200, res)
      end

      -- Check the cache on every node
      for _, v in ipairs({NODES.servroot1, NODES.servroot2, NODES.servroot3}) do
        local api_client = assert(helpers.http_client("127.0.0.1", pl_stringx.split(v.admin_listen, ":")[2]))
        local res = assert(api_client:send {
          method = "GET",
          path = "/cache/"..cache.all_apis_by_dict_key(),
          headers = {}
        })
        local body = cjson.decode(assert.res_status(200, res))
        assert.equal(1, pl_tablex.size(body.by_dns))
      end

      -- The cluster status is "active" for all three nodes
      local node_name
      for _, v in ipairs({NODES.servroot1, NODES.servroot2, NODES.servroot3}) do
        local api_client = assert(helpers.http_client("127.0.0.1", pl_stringx.split(v.admin_listen, ":")[2]))
        local res = assert(api_client:send {
          method = "GET",
          path = "/cluster/",
          headers = {}
        })
        local body = cjson.decode(assert.res_status(200, res))
        for _, v in ipairs(body.data) do
          assert.equal("alive", v.status)
          if not node_name and pl_stringx.split(v.address, ":")[2] == pl_stringx.split(NODES.servroot2.cluster_listen, ":")[2] then
            node_name = v.name
          end
        end
      end

      -- Kill one Serf
      os.execute(string.format("kill `cat %s` >/dev/null 2>&1", NODES.servroot2.prefix.."/pids/serf.pid"))

      -- Wait until the node becomes failed
      helpers.wait_until(function()
        local res = assert(api_client:send {
          method = "GET",
          path = "/cluster/",
          headers = {}
        })
        local body = cjson.decode(assert.res_status(200, res))
        for _, v in ipairs(body.data) do
          if v.status == "failed" then
            return true
          else -- No "left" nodes. It's either "alive" or "failed"
            assert.equal("alive", v.status)
          end
        end
      end, 60)

      -- The member has now failed, let's bring him up again
      os.execute(string.format("serf agent -profile=wan -node=%s -rpc-addr=%s"
                             .." -bind=%s event-handler=member-join,"
                             .."member-leave,member-failed,member-update,"
                             .."member-reap,user:kong=%s/serf/serf_event.sh > /dev/null &",
                            node_name,
                            NODES.servroot2.cluster_listen_rpc,
                            NODES.servroot2.cluster_listen,
                            NODES.servroot2.prefix))

      -- Now wait until the nodes becomes active again
      helpers.wait_until(function()
        local res = assert(api_client:send {
          method = "GET",
          path = "/cluster/"
        })
        local body = cjson.decode(assert.res_status(200, res))
        for _, v in ipairs(body.data) do
          if v.status == "failed" then
            return false
          end
        end
        return true
      end, 60)

      -- The cache should have been deleted on every node available
      for _, v in ipairs({NODES.servroot1, NODES.servroot2, NODES.servroot3}) do
        local api_client = assert(helpers.http_client("127.0.0.1", pl_stringx.split(v.admin_listen, ":")[2]))
        helpers.wait_until(function()
          local res = assert(api_client:send {
            method = "GET",
            path = "/cache/"..cache.all_apis_by_dict_key(),
            headers = {}
          })
          res:read_body()
          return res.status == 404
        end, 5)
      end
    end)
  end)

end)
