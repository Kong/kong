local spec_helper = require "spec.spec_helpers"
local yaml = require "yaml"
local IO = require "kong.tools.io"
local http_client = require "kong.tools.http_client"
local cjson = require "cjson"

local TEST_CONF = spec_helper.get_env().conf_file
local SERVER_CONF = "kong_TEST_SERVER.yml"

local API_URL = spec_helper.API_URL
local PROXY_URL = spec_helper.PROXY_URL

local SECOND_API_PORT = 9001
local SECOND_API_URL = "http://127.0.0.1:"..SECOND_API_PORT

local SECOND_PROXY_PORT = 9000
local SECOND_PROXY_URL = "http://127.0.0.1:"..SECOND_PROXY_PORT

local SECOND_SERVER_PROPERTIES = {
  nginx_working_dir = "nginx_tmp_2",
  proxy_listen = "0.0.0.0:"..SECOND_PROXY_PORT,
  proxy_listen_ssl = "0.0.0.0:9443",
  admin_api_listen = "0.0.0.0:"..SECOND_API_PORT,
  cluster_listen = "0.0.0.0:9946",
  cluster_listen_rpc = "0.0.0.0:9373",
  dns_resolvers_available = {
    dnsmasq = {port = 8054}
  }
}

local function replace_property(configuration, new_key, new_value)
  if type(new_value) == "table" then
    for k, v in pairs(new_value) do
      if not configuration[new_key] then configuration[new_key] = {} end
      configuration[new_key][k] = v
    end
  else
    configuration[new_key] = new_value
  end
  return configuration
end

local function replace_conf_property(t, output_file)
  if not output_file then output_file = SERVER_CONF end

  local yaml_value = yaml.load(IO.read_file(TEST_CONF))
  for k, v in pairs(t) do
    yaml_value = replace_property(yaml_value, k, v)
  end
  local new_config_content = yaml.dump(yaml_value)
  
  -- Workaround for https://github.com/lubyk/yaml/issues/2
  -- This workaround is in two places. To remove it "Find and replace" in the code
  new_config_content = string.gsub(new_config_content, "(%w+:%s*)([%w%.]+:%d+)", "%1\"%2\"")

  local ok = IO.write_to_file(output_file, new_config_content)
  assert.truthy(ok)
end

describe("Cluster", function()

  local SECOND_WORKING_DIR = "nginx_tmp_2"

  setup(function()
    pcall(spec_helper.stop_kong, TEST_CONF)

    spec_helper.prepare_db()

    os.execute("cp "..TEST_CONF.." "..SERVER_CONF)
    os.execute("mkdir -p "..SECOND_WORKING_DIR)
    spec_helper.add_env(SERVER_CONF)
    spec_helper.prepare_db(SERVER_CONF)
    replace_conf_property(SECOND_SERVER_PROPERTIES)
  end)

  teardown(function()
    os.remove(SERVER_CONF)
    os.execute("rm -rf "..SECOND_WORKING_DIR)
    spec_helper.remove_env(SERVER_CONF)
  end)

  after_each(function()
    pcall(spec_helper.stop_kong, TEST_CONF) 
    pcall(spec_helper.stop_kong, SERVER_CONF)
  end)

  it("should register the node on startup", function()
    local _, exit_code = spec_helper.start_kong(TEST_CONF, true)
    assert.are.same(0, exit_code)

    local _, status = http_client.get(API_URL)
    assert.equal(200, status) -- is running

    while(#spec_helper.envs[TEST_CONF].dao_factory.nodes:find_by_keys({}) ~= 1) do
      -- Wait
    end

    local res, err = spec_helper.envs[TEST_CONF].dao_factory.nodes:find_by_keys({})
    assert.falsy(err)
    assert.equal(1, #res)
    assert.truthy(res[1].created_at)
    assert.truthy(res[1].name)
    assert.truthy(res[1].cluster_listening_address)

    local res, status = http_client.get(API_URL.."/cluster")
    assert.equal(200, status)
    assert.equal(1, cjson.decode(res).total)
  end)
  
  it("should register the node on startup with the advertised address", function()
    SECOND_SERVER_PROPERTIES.cluster = {advertise = "5.5.5.5:1234"}
    replace_conf_property(SECOND_SERVER_PROPERTIES)

    local _, exit_code = spec_helper.start_kong(SERVER_CONF, true)
    assert.are.same(0, exit_code)

    local _, status = http_client.get(SECOND_API_URL)
    assert.equal(200, status) -- is running

    while(#spec_helper.envs[SERVER_CONF].dao_factory.nodes:find_by_keys({}) ~= 1) do
      -- Wait
    end

    local res, err = spec_helper.envs[SERVER_CONF].dao_factory.nodes:find_by_keys({})
    assert.falsy(err)
    assert.equal(1, #res)
    assert.truthy(res[1].created_at)
    assert.truthy(res[1].name)
    assert.truthy(res[1].cluster_listening_address)
    assert.equal("5.5.5.5:1234", res[1].cluster_listening_address)

    local res, status = http_client.get(SECOND_API_URL.."/cluster")
    assert.equal(200, status)
    assert.equal(1, cjson.decode(res).total)
    assert.equal("5.5.5.5:1234", cjson.decode(res).data[1].address)

    SECOND_SERVER_PROPERTIES.cluster = {advertise = ""}
    replace_conf_property(SECOND_SERVER_PROPERTIES)
  end)

  it("should register the second node on startup and auto-join sequentially", function()
    SECOND_SERVER_PROPERTIES.cluster = {["auto-join"] = true}
    replace_conf_property(SECOND_SERVER_PROPERTIES)

    local _, exit_code = spec_helper.start_kong(TEST_CONF, true)
    assert.are.same(0, exit_code)

    local _, status = http_client.get(API_URL)
    assert.equal(200, status) -- is running

    while(#spec_helper.envs[TEST_CONF].dao_factory.nodes:find_by_keys({}) ~= 1) do
      -- Wait
    end

    local _, exit_code = spec_helper.start_kong(SERVER_CONF, true)
    assert.are.same(0, exit_code)

    while(#spec_helper.envs[TEST_CONF].dao_factory.nodes:find_by_keys({}) ~= 2) do
      -- Wait
    end

    local res, err = spec_helper.envs[TEST_CONF].dao_factory.nodes:find_by_keys({})
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
      local res, status = http_client.get(API_URL.."/cluster")
      assert.equal(200, status)
      total = cjson.decode(res).total
    until(total == 2)

    local res, status = http_client.get(API_URL.."/cluster")
    assert.equal(200, status)
    assert.equal(2, cjson.decode(res).total)

    local res, status = http_client.get(SECOND_API_URL.."/cluster")
    assert.equal(200, status)
    assert.equal(2, cjson.decode(res).total)
  end)
  
  it("should register the second node on startup and auto-join asyncronously", function()
    local _, exit_code = spec_helper.start_kong(TEST_CONF, true)
    assert.are.same(0, exit_code)

    local _, exit_code = spec_helper.start_kong(SERVER_CONF, true)
    assert.are.same(0, exit_code)

    while(#spec_helper.envs[TEST_CONF].dao_factory.nodes:find_by_keys({}) ~= 2) do
      -- Wait
    end

    os.execute("sleep 5")

    local res, err = spec_helper.envs[TEST_CONF].dao_factory.nodes:find_by_keys({})
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
      local res, status = http_client.get(API_URL.."/cluster")
      assert.equal(200, status)
      total = cjson.decode(res).total
    until(total == 2)

    local res, status = http_client.get(API_URL.."/cluster")
    assert.equal(200, status)
    assert.equal(2, cjson.decode(res).total)

    local res, status = http_client.get(SECOND_API_URL.."/cluster")
    assert.equal(200, status)
    assert.equal(2, cjson.decode(res).total)
  end)

  it("should not join the second node on startup when auto-join is false", function()
    SECOND_SERVER_PROPERTIES.cluster = {["auto-join"] = false}
    replace_conf_property(SECOND_SERVER_PROPERTIES)

    local _, exit_code = spec_helper.start_kong(TEST_CONF, true)
    assert.are.same(0, exit_code)

    while(#spec_helper.envs[TEST_CONF].dao_factory.nodes:find_by_keys({}) ~= 1) do
      -- Wait
    end

    local _, exit_code = spec_helper.start_kong(SERVER_CONF, true)
    assert.are.same(0, exit_code)

    while(#spec_helper.envs[TEST_CONF].dao_factory.nodes:find_by_keys({}) ~= 2) do
      -- Wait
    end

    local res, err = spec_helper.envs[TEST_CONF].dao_factory.nodes:find_by_keys({})
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
      local res, status = http_client.get(API_URL.."/cluster")
      assert.equal(200, status)
      total = cjson.decode(res).total
    until(total == 1)

    local res, status = http_client.get(API_URL.."/cluster")
    assert.equal(200, status)
    assert.equal(1, cjson.decode(res).total)

    local res, status = http_client.get(SECOND_API_URL.."/cluster")
    assert.equal(200, status)
    assert.equal(1, cjson.decode(res).total)
  end)

  it("cache should be purged on the node that joins", function()
    replace_conf_property({cluster = {["auto-join"] = false}}, TEST_CONF)
    SECOND_SERVER_PROPERTIES.cluster = {["auto-join"] = false}
    replace_conf_property(SECOND_SERVER_PROPERTIES)

    -- Start the nodes
    local _, exit_code = spec_helper.start_kong(TEST_CONF, true)
    assert.are.same(0, exit_code)
    local _, exit_code = spec_helper.start_kong(SERVER_CONF, true)
    assert.are.same(0, exit_code)

    while(#spec_helper.envs[TEST_CONF].dao_factory.nodes:find_by_keys({}) ~= 2) do
      -- Wait
    end

    -- The nodes are sharing the same datastore, but not the same cluster

    -- Adding an API
    local res, status = http_client.post(API_URL.."/apis", {request_host="test.com", upstream_url="http://mockbin.org"})
    assert.equal(201, status)
    local api = cjson.decode(res)

    -- Populating the cache on both nodes
    local _, status = http_client.get(PROXY_URL.."/request", {}, {host = "test.com"})
    assert.equal(200, status)
    local _, status = http_client.get(SECOND_PROXY_URL.."/request", {}, {host = "test.com"})
    assert.equal(200, status)

    -- Updating API on first node
    local _, status = http_client.patch(API_URL.."/apis/"..api.id, {request_host="test2.com"})
    assert.equal(200, status)

    -- Making the request again on both nodes (the second node still process correctly the request)
    local _, status = http_client.get(PROXY_URL.."/request", {}, {host = "test.com"})
    assert.equal(404, status)
    local _, status = http_client.get(SECOND_PROXY_URL.."/request", {}, {host = "test.com"})
    assert.equal(200, status)

    -- Making the request again with the updated property (only the first node processes this correctly)
    local _, status = http_client.get(PROXY_URL.."/request", {}, {host = "test2.com"})
    assert.equal(200, status)
    local _, status = http_client.get(SECOND_PROXY_URL.."/request", {}, {host = "test2.com"})
    assert.equal(404, status)

    -- Joining the nodes in the same cluster
    local _, exit_code = IO.os_execute("serf join -rpc-addr=127.0.0.1:9101 join 127.0.0.1:9946")
    assert.are.same(0, exit_code)
    -- Wait for join to complete
    local total
    repeat
      local res, status = http_client.get(API_URL.."/cluster")
      assert.equal(200, status)
      total = cjson.decode(res).total
    until(total == 2)

    -- Wait for cache purge to be executed by the hooks
    os.execute("sleep 5")

    -- Making the request again on the new property, and now both nodes should work
    local _, status = http_client.get(PROXY_URL.."/request", {}, {host = "test2.com"})
    assert.equal(200, status)
    local _, status = http_client.get(SECOND_PROXY_URL.."/request", {}, {host = "test2.com"})
    assert.equal(200, status)

    -- And it should not work on both on the old DNS
    local _, status = http_client.get(PROXY_URL.."/request", {}, {host = "test.com"})
    assert.equal(404, status)
    local _, status = http_client.get(SECOND_PROXY_URL.."/request", {}, {host = "test.com"})
    assert.equal(404, status)

    --------------------------------------------------------
    -- Bring back the auto-join for the default test FILE --
    --------------------------------------------------------
    replace_conf_property({cluster = {["auto-join"] = true}}, TEST_CONF)
  end)

end)