local spec_helper = require "spec.spec_helpers"
local yaml = require "yaml"
local IO = require "kong.tools.io"
local http_client = require "kong.tools.http_client"
local cjson = require "cjson"
local stringy = require "stringy"
local cache = require "kong.tools.database_cache"
local utils = require "kong.tools.utils"

local TEST_CONF = spec_helper.get_env().conf_file

local SERVERS = {
  ["kong_CLUSTER_1.yml"] = {
    nginx_working_dir = "nginx_tmp_1",
    proxy_listen = "0.0.0.0:9000",
    proxy_listen_ssl = "0.0.0.0:9443",
    admin_api_listen = "0.0.0.0:9001",
    cluster_listen = "0.0.0.0:9946",
    cluster_listen_rpc = "0.0.0.0:9373",
    dns_resolvers_available = {
      dnsmasq = {port = 8054}
    }
  },
  ["kong_CLUSTER_2.yml"] = {
    nginx_working_dir = "nginx_tmp_2",
    proxy_listen = "0.0.0.0:10000",
    proxy_listen_ssl = "0.0.0.0:10443",
    admin_api_listen = "0.0.0.0:10001",
    cluster_listen = "0.0.0.0:10946",
    cluster_listen_rpc = "0.0.0.0:10373",
    dns_resolvers_available = {
      dnsmasq = {port = 10054}
    }
  },
  ["kong_CLUSTER_3.yml"] = {
    nginx_working_dir = "nginx_tmp_3",
    proxy_listen = "0.0.0.0:20000",
    proxy_listen_ssl = "0.0.0.0:20443",
    admin_api_listen = "0.0.0.0:20001",
    cluster_listen = "0.0.0.0:20946",
    cluster_listen_rpc = "0.0.0.0:20373",
    dns_resolvers_available = {
      dnsmasq = {port = 20054}
    }
  }
}

local SERVER_CONFS = {}
for k, _ in pairs(SERVERS) do
  table.insert(SERVER_CONFS, k)
end

local function replace_properties(t, output_file)
  local yaml_value = yaml.load(IO.read_file(output_file))
  for k, v in pairs(t) do
    if type(v) == "table" then
      if not yaml_value[k] then yaml_value[k] = {} end
      for sub_k, sub_v in pairs(v) do
        yaml_value[k][sub_k] = sub_v
      end
    else
      yaml_value[k] = v
    end
  end
  local new_config_content = yaml.dump(yaml_value)

  -- Workaround for https://github.com/lubyk/yaml/issues/2
  -- This workaround is in two places. To remove it "Find and replace" in the code
  new_config_content = string.gsub(new_config_content, "(%w+:%s*)([%w%.]+:%d+)", "%1\"%2\"")

  local ok = IO.write_to_file(output_file, new_config_content)
  assert.truthy(ok)
end

describe("Cluster", function()

  before_each(function()
    spec_helper.prepare_db()

    for k, v in pairs(SERVERS) do
      os.execute("cp "..TEST_CONF.." "..k.." && mkdir -p "..v.nginx_working_dir)
      replace_properties(v, k)
      spec_helper.add_env(k)
    end
  end)

  after_each(function()
    for k, v in pairs(SERVERS) do
      pcall(spec_helper.stop_kong, k)
      os.execute("rm "..k.." && rm -rf "..v.nginx_working_dir)
      spec_helper.remove_env(k)
    end
  end)

  describe("Nodes", function()
    it("should register the node on startup", function()
      local _, exit_code = spec_helper.start_kong(SERVER_CONFS[1])
      assert.are.same(0, exit_code)

      local api_url = "http://127.0.0.1:"..stringy.split(SERVERS[SERVER_CONFS[1]].admin_api_listen, ":")[2]

      local _, status = http_client.get(api_url)
      assert.equal(200, status) -- is running

      while(#spec_helper.envs[SERVER_CONFS[1]].dao_factory.nodes:find_all() ~= 1) do
        -- Wait
      end

      local res, err = spec_helper.envs[SERVER_CONFS[1]].dao_factory.nodes:find_all()
      assert.falsy(err)
      assert.equal(1, #res)
      assert.truthy(res[1].created_at)
      assert.truthy(res[1].name)
      assert.truthy(res[1].cluster_listening_address)

      local res, status = http_client.get(api_url.."/cluster")
      assert.equal(200, status)
      assert.equal(1, cjson.decode(res).total)
    end)
    it("should register the node on startup with the advertised address", function()
      -- Changing advertise property
      local properties = utils.deep_copy(SERVERS[SERVER_CONFS[1]])
      properties.cluster = { advertise = "5.5.5.5:1234" }
      replace_properties(properties, SERVER_CONFS[1])

      local _, exit_code = spec_helper.start_kong(SERVER_CONFS[1])
      assert.are.same(0, exit_code)

      local api_url = "http://127.0.0.1:"..stringy.split(SERVERS[SERVER_CONFS[1]].admin_api_listen, ":")[2]
      local _, status = http_client.get(api_url)
      assert.equal(200, status) -- is running

      while(#spec_helper.envs[SERVER_CONFS[1]].dao_factory.nodes:find_all() ~= 1) do
        -- Wait
      end

      local res, err = spec_helper.envs[SERVER_CONFS[1]].dao_factory.nodes:find_all()
      assert.falsy(err)
      assert.equal(1, #res)
      assert.truthy(res[1].created_at)
      assert.truthy(res[1].name)
      assert.truthy(res[1].cluster_listening_address)
      assert.equal("5.5.5.5:1234", res[1].cluster_listening_address)

      local res, status = http_client.get(api_url.."/cluster")
      assert.equal(200, status)
      assert.equal(1, cjson.decode(res).total)
      assert.equal("5.5.5.5:1234", cjson.decode(res).data[1].address)
    end)
  end)

  describe("Auto-join", function()
    it("should register the second node on startup and auto-join sequentially", function()
      local _, exit_code = spec_helper.start_kong(SERVER_CONFS[1])
      assert.are.same(0, exit_code)

      local api_url1 = "http://127.0.0.1:"..stringy.split(SERVERS[SERVER_CONFS[1]].admin_api_listen, ":")[2]
      local _, status = http_client.get(api_url1)
      assert.equal(200, status) -- is running

      while(#spec_helper.envs[SERVER_CONFS[1]].dao_factory.nodes:find_all() ~= 1) do
        -- Wait
      end

      local _, exit_code = spec_helper.start_kong(SERVER_CONFS[2])
      assert.are.same(0, exit_code)

      local api_url2 = "http://127.0.0.1:"..stringy.split(SERVERS[SERVER_CONFS[2]].admin_api_listen, ":")[2]
      local _, status = http_client.get(api_url2)
      assert.equal(200, status) -- is running

      while(#spec_helper.envs[SERVER_CONFS[1]].dao_factory.nodes:find_all() ~= 2) do
        -- Wait
      end

      local res, err = spec_helper.envs[SERVER_CONFS[1]].dao_factory.nodes:find_all()
      assert.falsy(err)
      assert.equal(2, #res)
      assert.truthy(res[1].created_at)
      assert.truthy(res[1].name)
      assert.truthy(res[1].cluster_listening_address)
      assert.truthy(res[2].created_at)
      assert.truthy(res[2].name)
      assert.truthy(res[2].cluster_listening_address)

      local total
      repeat
        local res, status = http_client.get(api_url1.."/cluster")
        assert.equal(200, status)
        total = cjson.decode(res).total
      until(total == 2)

      local res, status = http_client.get(api_url1.."/cluster")
      assert.equal(200, status)
      assert.equal(2, cjson.decode(res).total)

      local res, status = http_client.get(api_url2.."/cluster")
      assert.equal(200, status)
      assert.equal(2, cjson.decode(res).total)
    end)

    it("should register the second node on startup and auto-join asyncronously", function()
      local _, exit_code = spec_helper.start_kong(SERVER_CONFS[1])
      assert.are.same(0, exit_code)

      local _, exit_code = spec_helper.start_kong(SERVER_CONFS[2])
      assert.are.same(0, exit_code)

      while(#spec_helper.envs[SERVER_CONFS[1]].dao_factory.nodes:find_all() ~= 2) do
        -- Wait
      end

      -- We need to wait a few seconds for the async job kick in and join the nodes together
      os.execute("sleep 5")

      local res, err = spec_helper.envs[SERVER_CONFS[1]].dao_factory.nodes:find_all()
      assert.falsy(err)
      assert.equal(2, #res)
      assert.truthy(res[1].created_at)
      assert.truthy(res[1].name)
      assert.truthy(res[1].cluster_listening_address)
      assert.truthy(res[2].created_at)
      assert.truthy(res[2].name)
      assert.truthy(res[2].cluster_listening_address)

      local api_url1 = "http://127.0.0.1:"..stringy.split(SERVERS[SERVER_CONFS[1]].admin_api_listen, ":")[2]
      local api_url2 = "http://127.0.0.1:"..stringy.split(SERVERS[SERVER_CONFS[2]].admin_api_listen, ":")[2]
      local total
      repeat
        local res, status = http_client.get(api_url1.."/cluster")
        assert.equal(200, status)
        total = cjson.decode(res).total
      until(total == 2)

      local res, status = http_client.get(api_url1.."/cluster")
      assert.equal(200, status)
      assert.equal(2, cjson.decode(res).total)

      local res, status = http_client.get(api_url2.."/cluster")
      assert.equal(200, status)
      assert.equal(2, cjson.decode(res).total)
    end)

    it("should not join the second node on startup when auto-join is false", function()
      -- Changing auto-join property
      local properties = utils.deep_copy(SERVERS[SERVER_CONFS[1]])
      properties.cluster = { ["auto-join"] = false }
      replace_properties(properties, SERVER_CONFS[1])
      properties = utils.deep_copy(SERVERS[SERVER_CONFS[2]])
      properties.cluster = { ["auto-join"] = false }
      replace_properties(properties, SERVER_CONFS[2])

      local _, exit_code = spec_helper.start_kong(SERVER_CONFS[1])
      assert.are.same(0, exit_code)

      while(#spec_helper.envs[SERVER_CONFS[1]].dao_factory.nodes:find_all() ~= 1) do
        -- Wait
      end

      local _, exit_code = spec_helper.start_kong(SERVER_CONFS[2])
      assert.are.same(0, exit_code)

      while(#spec_helper.envs[SERVER_CONFS[1]].dao_factory.nodes:find_all() ~= 2) do
        -- Wait
      end

      local res, err = spec_helper.envs[SERVER_CONFS[1]].dao_factory.nodes:find_all()
      assert.falsy(err)
      assert.equal(2, #res)
      assert.truthy(res[1].created_at)
      assert.truthy(res[1].name)
      assert.truthy(res[1].cluster_listening_address)
      assert.truthy(res[2].created_at)
      assert.truthy(res[2].name)
      assert.truthy(res[2].cluster_listening_address)

      local api_url1 = "http://127.0.0.1:"..stringy.split(SERVERS[SERVER_CONFS[1]].admin_api_listen, ":")[2]
      local api_url2 = "http://127.0.0.1:"..stringy.split(SERVERS[SERVER_CONFS[2]].admin_api_listen, ":")[2]
      local total
      repeat
        local res, status = http_client.get(api_url1.."/cluster")
        assert.equal(200, status)
        total = cjson.decode(res).total
      until(total == 1)

      local res, status = http_client.get(api_url1.."/cluster")
      assert.equal(200, status)
      assert.equal(1, cjson.decode(res).total)

      local res, status = http_client.get(api_url2.."/cluster")
      assert.equal(200, status)
      assert.equal(1, cjson.decode(res).total)
    end)
  end)
  
  describe("Cache purges", function()
    it("must purge cache on all nodes on member-join", function()
      local _, exit_code = spec_helper.start_kong(SERVER_CONFS[1])
      assert.are.equal(0, exit_code)

      while(#spec_helper.envs[SERVER_CONFS[1]].dao_factory.nodes:find_all() ~= 1) do
        -- Wait
      end

      local proxy_url1 = "http://127.0.0.1:"..stringy.split(SERVERS[SERVER_CONFS[1]].proxy_listen, ":")[2]
      local api_url1 = "http://127.0.0.1:"..stringy.split(SERVERS[SERVER_CONFS[1]].admin_api_listen, ":")[2]
      local api_url2 = "http://127.0.0.1:"..stringy.split(SERVERS[SERVER_CONFS[2]].admin_api_listen, ":")[2]

      -- Adding an API
      local _, status = http_client.post(api_url1.."/apis", {request_host="test.com", upstream_url="http://mockbin.org"})
      assert.equal(201, status)

      -- Wait for invalidation of API creation to propagate
      os.execute("sleep 5")

      -- Populating the cache
      local _, status = http_client.get(proxy_url1.."/request", {}, {host = "test.com"})
      assert.equal(200, status)

      -- Checking the element in the cache
      local _, status = http_client.get(api_url1.."/cache/"..cache.all_apis_by_dict_key())
      assert.equal(200, status)

      -- Starting second node
      local _, exit_code = spec_helper.start_kong(SERVER_CONFS[2])
      assert.are.equal(0, exit_code)

      while(#spec_helper.envs[SERVER_CONFS[2]].dao_factory.nodes:find_all() ~= 2) do
        -- Wait
      end

      -- Wait for event to propagate
      local status
      repeat
        _, status = http_client.get(api_url1.."/cache/"..cache.all_apis_by_dict_key())
      until(status ~= 200)

      -- The cache on the first node should be invalidated
      local _, status = http_client.get(api_url1.."/cache/"..cache.all_apis_by_dict_key())
      assert.equal(404, status)

      -- And the second node has no cache either because it was never invoked
      local _, status = http_client.get(api_url2.."/cache/"..cache.all_apis_by_dict_key())
      assert.equal(404, status)
    end)
  
    it("must purge cache on all nodes when a failed serf starts again (member-join event - simulation of a crash in a 3-node setup)", function()
      local _, exit_code = spec_helper.start_kong(SERVER_CONFS[1])
      assert.are.same(0, exit_code)

      local _, exit_code = spec_helper.start_kong(SERVER_CONFS[2])
      assert.are.same(0, exit_code)

      local _, exit_code = spec_helper.start_kong(SERVER_CONFS[3])
      assert.are.same(0, exit_code)

      while(#spec_helper.envs[SERVER_CONFS[1]].dao_factory.nodes:find_all() ~= 3) do
        -- Wait
      end

      local api_url1 = "http://127.0.0.1:"..stringy.split(SERVERS[SERVER_CONFS[1]].admin_api_listen, ":")[2]
      local api_url2 = "http://127.0.0.1:"..stringy.split(SERVERS[SERVER_CONFS[2]].admin_api_listen, ":")[2]
      local api_url3 = "http://127.0.0.1:"..stringy.split(SERVERS[SERVER_CONFS[3]].admin_api_listen, ":")[2]
      local total
      repeat
        local res, status = http_client.get(api_url1.."/cluster")
        assert.equals(200, status)
        total = cjson.decode(res).total
      until(total == 3)

      -- Now we have three nodes connected to each other, let's create and consume an API
      -- Adding an API
      local _, status = http_client.post(api_url1.."/apis", {request_host="test.com", upstream_url="http://mockbin.org"})
      assert.equal(201, status)

      os.execute("sleep 5")

      local proxy_url1 = "http://127.0.0.1:"..stringy.split(SERVERS[SERVER_CONFS[1]].proxy_listen, ":")[2]
      local proxy_url2 = "http://127.0.0.1:"..stringy.split(SERVERS[SERVER_CONFS[2]].proxy_listen, ":")[2]
      local proxy_url3 = "http://127.0.0.1:"..stringy.split(SERVERS[SERVER_CONFS[3]].proxy_listen, ":")[2]

      -- Populate the cache
      local _, status = http_client.get(proxy_url1.."/request", {}, {host = "test.com"})
      assert.equal(200, status)
      local _, status = http_client.get(proxy_url2.."/request", {}, {host = "test.com"})
      assert.equal(200, status)
      local _, status = http_client.get(proxy_url3.."/request", {}, {host = "test.com"})
      assert.equal(200, status)

      -- Check the cache
      local _, status = http_client.get(api_url1.."/cache/"..cache.all_apis_by_dict_key(), {})
      assert.equal(200, status)
      local _, status = http_client.get(api_url2.."/cache/"..cache.all_apis_by_dict_key(), {})
      assert.equal(200, status)
      local _, status = http_client.get(api_url3.."/cache/"..cache.all_apis_by_dict_key(), {})
      assert.equal(200, status)

      -- The status is active for all three
      local res = http_client.get(api_url1.."/cluster")
      for _, v in ipairs(cjson.decode(res).data) do
        assert.equals("alive", v.status)
      end

      -- Kill one serf
      local serf_pid = IO.read_file(SERVERS[SERVER_CONFS[2]].nginx_working_dir.."/serf.pid")
      assert.truthy(serf_pid)
      os.execute("kill -9 "..serf_pid)

      -- Now wait until the node becomes failed
      local has_failed
      local node_name
      repeat
        local res, status = http_client.get(api_url1.."/cluster")
        assert.equals(200, status)
        local body = cjson.decode(res)
        for _, v in ipairs(body.data) do
          if v.status == "failed" then
            has_failed = true
            node_name = v.name
            break  
          end
        end
        os.execute("sleep 1")
      until(has_failed)

      -- The member has now failed, let's bring him up again
      local current_dir = IO.os_execute("pwd")
      os.execute("serf agent -profile=local -node="..node_name.." -rpc-addr="..SERVERS[SERVER_CONFS[2]].cluster_listen_rpc.." -bind="..SERVERS[SERVER_CONFS[2]].cluster_listen.." -event-handler=member-join,member-leave,member-failed,member-update,member-reap,user:kong="..current_dir.."/"..SERVERS[SERVER_CONFS[2]].nginx_working_dir.."/serf_event.sh > /dev/null &")
      -- Now wait until the node becomes active again
      repeat
        local res, status = http_client.get(api_url1.."/cluster")
        assert.equals(200, status)
        local body = cjson.decode(res)
        local all_alive = true
        for _, v in ipairs(body.data) do
          if v.status == "failed" then
            all_alive = false
            break
          end
        end
        os.execute("sleep 1")
      until(not all_alive)

      -- The cache should have been deleted on every node
      -- Wait for event to propagate
      local all_invalidated
      repeat
        local _, status1 = http_client.get(api_url1.."/cache/"..cache.all_apis_by_dict_key())
        local _, status2 = http_client.get(api_url2.."/cache/"..cache.all_apis_by_dict_key())
        local _, status3 = http_client.get(api_url3.."/cache/"..cache.all_apis_by_dict_key())
        all_invalidated = (status1 == 404) and (status2 == 404) and (status3 == 404)
        os.execute("sleep 1")
      until(all_invalidated)

      -- The cache on every node should be invalidated
      local _, status = http_client.get(api_url1.."/cache/"..cache.all_apis_by_dict_key())
      assert.equal(404, status)
      local _, status = http_client.get(api_url2.."/cache/"..cache.all_apis_by_dict_key())
      assert.equal(404, status)
      local _, status = http_client.get(api_url3.."/cache/"..cache.all_apis_by_dict_key())
      assert.equal(404, status)
      
      os.execute("pkill -9 serf") -- Kill the serf we just started
    end)
  end)
end)