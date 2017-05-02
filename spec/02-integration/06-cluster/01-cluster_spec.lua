local cjson = require "cjson"
local helpers = require "spec.helpers"
local pl_tablex = require "pl.tablex"
local pl_stringx = require "pl.stringx"
local conf_loader = require "kong.conf_loader"

local CLIENT_TIMEOUT = 5000
local NODES_CONF = {}
local NODES = {
  servroot1 = {
    prefix = "servroot1",
    ssl = false,
    admin_ssl = false,
    proxy_listen = "127.0.0.1:9000",
    admin_listen = "0.0.0.0:9001",
    cluster_listen = "0.0.0.0:9946",
    cluster_listen_rpc = "0.0.0.0:9373",
    cluster_profile = "local",
    custom_plugins = "first-request",
  },
  servroot2 = {
    prefix = "servroot2",
    ssl = false,
    admin_ssl = false,
    proxy_listen = "127.0.0.1:10000",
    admin_listen = "0.0.0.0:10001",
    cluster_listen = "0.0.0.0:10946",
    cluster_listen_rpc = "0.0.0.0:10373",
    cluster_profile = "local",
    custom_plugins = "first-request",
  },
  servroot3 = {
    prefix = "servroot3",
    ssl = false,
    admin_ssl = false,
    proxy_listen = "127.0.0.1:20000",
    admin_listen = "0.0.0.0:20001",
    cluster_listen = "0.0.0.0:20946",
    cluster_listen_rpc = "0.0.0.0:20373",
    cluster_profile = "local",
    custom_plugins = "first-request",
  }
}

for k, v in pairs(NODES) do
  NODES_CONF[k] = conf_loader(nil, v)
end

describe("Cluster", function()
  before_each(function()
    for _, v in pairs(NODES) do
      helpers.prepare_prefix(v.prefix)
    end
  end)
  after_each(function()
    for _, v in pairs(NODES) do
      helpers.stop_kong(v.prefix)
    end
  end)

  describe("Nodes", function()
    it("should register the node on startup", function()
      assert(helpers.kong_exec("start --conf "..helpers.test_conf_path, NODES.servroot1))

      -- Wait for node to be registered
      helpers.wait_until(function()
        return helpers.dao.nodes:count() == 1
      end)

      local node = helpers.dao.nodes:find_all()[1]
      assert.is_number(node.created_at)
      assert.is_string(node.name)
      assert.is_string(node.cluster_listening_address)

      local api_client = helpers.http_client("127.0.0.1", NODES_CONF.servroot1.admin_port, CLIENT_TIMEOUT)
      local res = assert(api_client:send {
        method = "GET",
        path = "/cluster/"
      })
      local body = assert.res_status(200, res)
      local json = cjson.decode(body)
      assert.equal(1, json.total)
      assert.equal(node.name, json.data[1].name)
      assert.equal(node.cluster_listening_address, json.data[1].address)
      assert.equal("alive", json.data[1].status)
    end)

    it("should register the node on startup with the advertised address", function()
      local conf = pl_tablex.deepcopy(NODES.servroot1)
      conf.cluster_advertise = "5.5.5.5:1234"

      assert(helpers.kong_exec("start --conf "..helpers.test_conf_path, conf))

      -- Wait for node to be registered
      helpers.wait_until(function()
        return helpers.dao.nodes:count() == 1
      end)

      local node = helpers.dao.nodes:find_all()[1]
      assert.is_number(node.created_at)
      assert.is_string(node.name)
      assert.equal("5.5.5.5:1234", node.cluster_listening_address)

      local api_client = helpers.http_client("127.0.0.1", NODES_CONF.servroot1.admin_port, CLIENT_TIMEOUT)
      local res = assert(api_client:send {
        method = "GET",
        path = "/cluster/"
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
      assert(helpers.kong_exec("start --conf "..helpers.test_conf_path, NODES.servroot1))
      -- Wait for first node to be registered
      helpers.wait_until(function()
        return helpers.dao.nodes:count() == 1
      end)

      assert(helpers.kong_exec("start --conf "..helpers.test_conf_path, NODES.servroot2))
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
      for _, v in ipairs({NODES_CONF.servroot1, NODES_CONF.servroot2}) do
        local api_client = helpers.http_client("127.0.0.1", v.admin_port, CLIENT_TIMEOUT)

        helpers.wait_until(function()
          local res = assert(api_client:send {
            method = "GET",
            path = "/cluster/"
          })
          local body = cjson.decode(assert.res_status(200, res))
          return body.total == 2
        end, 3)
      end
    end)

    it("should register the second node on startup and auto-join asynchronously", function()
      assert(helpers.kong_exec("start --conf "..helpers.test_conf_path, NODES.servroot1))
      assert(helpers.kong_exec("start --conf "..helpers.test_conf_path, NODES.servroot2))
      assert(helpers.kong_exec("start --conf "..helpers.test_conf_path, NODES.servroot3))

      -- We need to wait a few seconds for the async job to kick in and join all the nodes together
      helpers.wait_until(function()
        local _, _, stdout = assert(helpers.execute(
                                 string.format("%s members -format=json -rpc-addr=%s",
                                   helpers.test_conf.serf_path, NODES.servroot1.cluster_listen_rpc)
                               )
                             )
        return #cjson.decode(stdout).members == 3
      end, 5)

      -- Wait for nodes to be registered in Serf in both nodes
      for _, v in ipairs(NODES_CONF) do
        local api_client = helpers.http_client("127.0.0.1", v.admin_port, CLIENT_TIMEOUT)

        helpers.wait_until(function()
          local res = assert(api_client:send {
            method = "GET",
            path = "/cluster/"
          })
          local body = cjson.decode(assert.res_status(200, res))
          return body.total == 3
        end, 3)
      end
    end)
  end)

  describe("Cache purges", function()
    it("must purge cache on all nodes on member-join", function()
      assert(helpers.kong_exec("start --conf "..helpers.test_conf_path, NODES.servroot1))
      -- Wait for first node to be registered
      helpers.wait_until(function()
        return helpers.dao.nodes:count() == 1
      end)

      -- adding an API
      local api_client = helpers.http_client("127.0.0.1", NODES_CONF.servroot1.admin_port, CLIENT_TIMEOUT)
      local res = assert(api_client:send {
        method = "POST",
        path = "/apis/",
        headers = {
          ["Content-Type"] = "application/json"
        },
        body = {
          name = "test",
          hosts = { "test.com" },
          upstream_url = "http://mockbin.org"
        }
      })
      assert.res_status(201, res)
      -- adding the first-request plugin
      local res = assert(api_client:send {
        method = "POST",
        path = "/apis/test/plugins/",
        headers = {
          ["Content-Type"] = "application/json"
        },
        body = {
          name = "first-request"
        }
      })
      assert.res_status(201, res)

      ngx.sleep(5) -- Wait for invalidation of API creation to propagate

      -- Populate the cache
      local client = helpers.http_client("127.0.0.1", NODES_CONF.servroot1.proxy_port, CLIENT_TIMEOUT)
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
        path = "/cache/requested"
      })
      local body = cjson.decode(assert.res_status(200, res))
      assert.True(body.requested)

      -- Starting second node
      assert(helpers.kong_exec("start --conf "..helpers.test_conf_path, NODES.servroot2))
      -- Wait for the second node to be registered
      helpers.wait_until(function()
        return helpers.dao.nodes:count() == 2
      end)

      -- The cache on the first node should be invalidated, and the second node has no cache either because it was never invoked
      for _, v in ipairs({NODES_CONF.servroot1, NODES_CONF.servroot2}) do
        local api_client = helpers.http_client("127.0.0.1", v.admin_port, CLIENT_TIMEOUT)

        helpers.wait_until(function()
          local res = assert(api_client:send {
            method = "GET",
            path = "/cache/requested"
          })
          res:read_body()
          return res.status == 404
        end)
      end
    end)

    it("must purge cache on all nodes when a failed serf starts again (member-join event - simulation of a crash in a 3-node setup)", function()
      assert(helpers.kong_exec("start --conf "..helpers.test_conf_path, NODES.servroot1))
      assert(helpers.kong_exec("start --conf "..helpers.test_conf_path, NODES.servroot2))
      assert(helpers.kong_exec("start --conf "..helpers.test_conf_path, NODES.servroot3))

      helpers.wait_until(function()
        local api_client = helpers.http_client("127.0.0.1", NODES_CONF.servroot1.admin_port, CLIENT_TIMEOUT)
        local res = assert(api_client:send {
          method = "GET",
          path = "/cluster/"
        })
        local body = cjson.decode(assert.res_status(200, res))
        api_client:close()
        return body.total == 3
      end, 10)

      -- Now we have three nodes connected to each other, let's create and consume an API
      -- Adding an API
      local api_client = helpers.http_client("127.0.0.1", NODES_CONF.servroot1.admin_port, CLIENT_TIMEOUT)
      local res = assert(api_client:send {
        method = "POST",
        path = "/apis/",
        headers = {
          ["Content-Type"] = "application/json"
        },
        body = {
          name = "test",
          hosts = { "test.com" },
          upstream_url = "http://mockbin.org"
        }
      })
      assert.res_status(201, res)
      -- adding the first-request plugin
      local res = assert(api_client:send {
        method = "POST",
        path = "/apis/test/plugins/",
        headers = {
          ["Content-Type"] = "application/json"
        },
        body = {
          name = "first-request"
        }
      })
      assert.res_status(201, res)
      api_client:close()

      ngx.sleep(5) -- Wait for invalidation of API creation to propagate

      -- Populate the cache on every node
      for _, v in pairs(NODES_CONF) do
        local api_client = helpers.http_client("127.0.0.1", v.proxy_port, CLIENT_TIMEOUT)
        local res = assert(api_client:send {
          method = "GET",
          path = "/status/200",
          headers = {
            ["Host"] = "test.com"
          }
        })
        assert.res_status(200, res)
        api_client:close()
      end

      -- Check the cache on every node
      for _, v in pairs(NODES_CONF) do
        local api_client = helpers.http_client("127.0.0.1", v.admin_port, CLIENT_TIMEOUT)
        local res = assert(api_client:send {
          method = "GET",
          path = "/cache/requested"
        })
        local body = cjson.decode(assert.res_status(200, res))
        api_client:close()
        assert.True(body.requested)
      end

      -- The cluster status is "active" for all three nodes
      local node_name
      for _, v in pairs(NODES_CONF) do
        local api_client = helpers.http_client("127.0.0.1", v.admin_port, CLIENT_TIMEOUT)
        local res = assert(api_client:send {
          method = "GET",
          path = "/cluster/"
        })
        local body = cjson.decode(assert.res_status(200, res))
        api_client:close()
        for _, v in ipairs(body.data) do
          assert.equal("alive", v.status)
          if not node_name and pl_stringx.split(v.address, ":")[2] == pl_stringx.split(NODES.servroot2.cluster_listen, ":")[2] then
            node_name = v.name
          end
        end
      end

      -- Kill one Serf
      assert(helpers.execute(string.format("kill `cat %s` >/dev/null 2>&1", NODES_CONF.servroot2.serf_pid)))

      -- Wait until the node becomes failed
      helpers.wait_until(function()
        local api_client = helpers.http_client("127.0.0.1", NODES_CONF.servroot1.admin_port, CLIENT_TIMEOUT)
        local res = assert(api_client:send {
          method = "GET",
          path = "/cluster/"
        })
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        api_client:close()
        for _, v in ipairs(json.data) do
          if v.status == "failed" then
            return true
          else -- No "left" nodes. It's either "alive" or "failed"
            assert.equal("alive", v.status)
          end
        end
      end, 30)

      assert(node_name, "node_name is nil")

      -- The member has now failed, let's bring it up again
      assert(helpers.execute(string.format("%s agent -profile=wan -node=%s -rpc-addr=%s"
                             .." -bind=%s -event-handler=member-join,"
                             .."member-leave,member-failed,member-update,"
                             .."member-reap,user:kong=%s > /dev/null &",
                            helpers.test_conf.serf_path,
                            node_name,
                            NODES.servroot2.cluster_listen_rpc,
                            NODES.servroot2.cluster_listen,
                            NODES_CONF.servroot2.serf_event)))

      -- Now wait until the node becomes active again
      helpers.wait_until(function()
        local api_client = helpers.http_client("127.0.0.1", NODES_CONF.servroot1.admin_port, CLIENT_TIMEOUT)
        local res = assert(api_client:send {
          method = "GET",
          path = "/cluster/"
        })
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        api_client:close()
        for _, v in ipairs(json.data) do
          if v.status == "failed" then
            return false
          end
        end
        return true
      end, 60)

      -- The cache should have been deleted on every node available
      for _, v in ipairs(NODES_CONF) do
        helpers.wait_until(function()
          local api_client = helpers.http_client("127.0.0.1", v.admin_port, CLIENT_TIMEOUT)
          local res = assert(api_client:send {
            method = "GET",
            path = "/cache/requested"
          })
          api_client:close()
          return res.status == 404
        end, 30)
      end
    end)
  end)
end)
