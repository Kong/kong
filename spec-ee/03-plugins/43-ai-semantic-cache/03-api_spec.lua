-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local helpers = require "spec.helpers"
local split = require "kong.tools.string".split
local cjson = require "cjson.safe"
local pl_file = require "pl.file"
local fmt = string.format

local MOCK_PORT = helpers.get_available_port()

local vectordb = require("kong.llm.vectordb")

local REDIS_HOST = os.getenv("KONG_SPEC_TEST_REDIS_STACK_HOST") or "127.0.0.1"
local REDIS_PORT = tonumber(os.getenv("KONG_SPEC_TEST_REDIS_STACK_PORT") or 16379)

local PLUGIN_NAME = "ai-semantic-cache"
local PLUGIN_ID = "54f597cb-6703-47ca-8533-30b516edccdc"
local vector_connector

local MOCK_FIXTURE = [[
  server {
    server_name llm;
    listen ]]..MOCK_PORT..[[;

    default_type 'application/json';

    location = "/embeddings" {
      content_by_lua_block {
        local pl_file = require "pl.file"

        ngx.status = 200
        ngx.print(pl_file.read("spec-ee/fixtures/ai-proxy/embeddings/response/good.json"))
      }
    }

    # llm mocks
    location = "/llm/v1/chat/good" {
      content_by_lua_block {
        local pl_file = require "pl.file"
        ngx.status = 200
        ngx.print(pl_file.read("spec-ee/fixtures/ai-proxy/chat/response/good.json"))
      }
    }
  }
]]

local good_request_body = pl_file.read("spec-ee/fixtures/ai-proxy/chat/request/good.json")

local function wait_until_key_in_cache(vector_connector, key)
  -- wait until key is in cache (we get a 200 on plugin API) and execute
  -- a test function if provided.
  helpers.wait_until(function()
    local res, err = vector_connector:keys(key)

    -- wait_until does not like asserts
    if not res or err then return false end

    if #res < 1 then
      return false
    end

    return res
  end, 5)
end

local VECTORDB_SETUP = {
  strategy = "redis",
  dimensions = 3072,
  distance_metric = "cosine",
  threshold = 0.7,
  redis = {
    host = REDIS_HOST,
    port = REDIS_PORT,  -- use the "other" redis, that includes RediSearch
  },
}

local EMBEDDINGS_SETUP = {
  auth = {
    header_name = "Authorization",
    header_value = "Bearer kong-key",
  },
  model = {
    provider = "openai",
    name = "text-embedding-3-large",
    options = {
      upstream_url = "http://"..helpers.mock_upstream_host..":"..MOCK_PORT.."/embeddings",
    },
  },
}

for _, strategy in helpers.all_strategies() do
  describe(PLUGIN_NAME .. ": (access) [#" .. strategy .. "]", function()
    -- setup
    local proxy_client, admin_client

    lazy_setup(function()
      local bp = helpers.get_db_utils(strategy == "off" and "postgres" or strategy, nil, { PLUGIN_NAME, "pre-function" })

      -- set up openai mock fixtures
      local fixtures = {
        http_mock = {},
      }
      fixtures.http_mock.llm = MOCK_FIXTURE

      local svc = assert(bp.services:insert {
        url = "http://"..helpers.mock_upstream_host..":"..MOCK_PORT.."/llm/v1/chat/good"
      })

      local rt = assert(bp.routes:insert {
        service = svc,
        protocols = { "http" },
        strip_path = true,
        paths = { "/llm" }
      })
      bp.plugins:insert {
        name = PLUGIN_NAME,
        id = PLUGIN_ID,
        route = { id = rt.id },
        config = {
          message_countback = 10,
          ignore_assistant_prompts = true,
          ignore_system_prompts = true,
          ignore_tool_prompts = true,
          stop_on_failure = true,
          embeddings = EMBEDDINGS_SETUP,
          vectordb = VECTORDB_SETUP,
        },
      }

      -- start kong
      assert(helpers.start_kong({
        -- set the strategy
        database   = strategy,
        -- use the custom test template to create a local mock server
        nginx_conf = "spec/fixtures/custom_nginx.template",
        -- make sure our plugin gets loaded
        plugins = "bundled," .. PLUGIN_NAME .. ",pre-function",
        -- write & load declarative config, only if 'strategy=off'
        declarative_config = strategy == "off" and helpers.make_yaml_file() or nil,
        -- let me read test files
        untrusted_lua_sandbox_requires = "pl.file,cjson.safe,kong.llm.state"
      }, nil, nil, fixtures))
    end)

    lazy_teardown(function()
      helpers.stop_kong()
    end)

    before_each(function()
      proxy_client = helpers.proxy_client()
      admin_client = helpers.admin_client()

      -- clear the vectordb for each test
      vector_connector = vector_connector
                      or vectordb.new("redis", fmt("kong_semantic_cache:%s", PLUGIN_ID), VECTORDB_SETUP)

      vector_connector:drop_index(true)
    end)

    after_each(function()
      if proxy_client then proxy_client:close() end
      if admin_client then admin_client:close() end

      -- clear the vectordb for each test
      vector_connector = vector_connector
                      or vectordb.new("redis", fmt("kong_semantic_cache:%s", PLUGIN_ID), VECTORDB_SETUP)

      vector_connector:drop_index(true)
    end)

    -- run
    describe("[GET] cache operations", function()
      it("can retrieve message from cache by global select", function()
        -- make llm request and trigger cache storage
        local r = proxy_client:post("/llm", {
          headers = {
            ["content-type"] = "application/json",
            ["accept"] = "application/json",
          },
          body = good_request_body,
        })

        assert.res_status(200 , r)
        local x_cache_status = assert.header("X-Cache-Status", r)
        assert.equals("Miss", x_cache_status)

        -- verify it's cached
        wait_until_key_in_cache(vector_connector, "kong_semantic_cache:" .. PLUGIN_ID .. ":*")

        local r = proxy_client:post("/llm", {
          headers = {
            ["content-type"] = "application/json",
            ["accept"] = "application/json",
          },
          body = good_request_body,
        })

        assert.res_status(200 , r)
        local x_cache_status = assert.header("X-Cache-Status", r)
        local x_cache_ttl = assert.header("X-Cache-Ttl", r)
        local x_cache_key = assert.header("X-Cache-Key", r)
        assert.equals("Hit", x_cache_status)
        assert.equals("300", x_cache_ttl)
        assert.equals("kong_semantic_cache", split(x_cache_key, ":")[1])

        -- try to read it back using admin api
        local pret, err = admin_client:get(fmt("/ai-semantic-cache/%s", x_cache_key))
        assert.is_nil(err)
        assert.equal(200, pret.status)
        
        local body, _ = pret:read_body()
        assert.not_nil(body)
        body = cjson.decode(body)

        -- test that our message is still there
        assert.equal("A train is a mode of transportation that typically runs on tracks and consists of a series of connected vehicles, " .. 
                     "called cars or carriages. Trains can transport passengers, cargo, or a combination of both. They are powered by various " .. 
                     "methods, including steam, diesel, and electricity. \n\nPassenger trains are designed to carry people and typically offer " ..
                     "various amenities such as seating, restrooms, and sometimes dining or sleeping facilities. Freight trains, on the other hand, " ..
                     "are designed to transport goods and materials and often",
                    body.choices[1].message.content)
      end)

      it("can retrieve message from cache by plugin-id specific", function()
        -- make llm request and trigger cache storage
        local r = proxy_client:post("/llm", {
          headers = {
            ["content-type"] = "application/json",
            ["accept"] = "application/json",
          },
          body = good_request_body,
        })

        assert.res_status(200 , r)
        local x_cache_status = assert.header("X-Cache-Status", r)
        assert.equals("Miss", x_cache_status)

        -- verify it's cached
        wait_until_key_in_cache(vector_connector, "kong_semantic_cache:" .. PLUGIN_ID .. ":*")

        local r = proxy_client:post("/llm", {
          headers = {
            ["content-type"] = "application/json",
            ["accept"] = "application/json",
          },
          body = good_request_body,
        })

        assert.res_status(200 , r)
        local x_cache_status = assert.header("X-Cache-Status", r)
        local x_cache_ttl = assert.header("X-Cache-Ttl", r)
        local x_cache_key = assert.header("X-Cache-Key", r)
        assert.equals("Hit", x_cache_status)
        assert.equals("300", x_cache_ttl)
        assert.equals("kong_semantic_cache", split(x_cache_key, ":")[1])

        -- try to read it back using admin api
        local pret, err = admin_client:get(fmt("/ai-semantic-cache/%s/caches/%s", PLUGIN_ID, x_cache_key))
        assert.is_nil(err)
        assert.equal(200, pret.status)
        
        local body, _ = pret:read_body()
        assert.not_nil(body)
        body = cjson.decode(body)

        -- test that our message is still there
        assert.equal("A train is a mode of transportation that typically runs on tracks and consists of a series of connected vehicles, " .. 
                     "called cars or carriages. Trains can transport passengers, cargo, or a combination of both. They are powered by various " .. 
                     "methods, including steam, diesel, and electricity. \n\nPassenger trains are designed to carry people and typically offer " ..
                     "various amenities such as seating, restrooms, and sometimes dining or sleeping facilities. Freight trains, on the other hand, " ..
                     "are designed to transport goods and materials and often",
                    body.choices[1].message.content)
      end)
    end)
    describe("[DELETE] cache operations", function()
      it("can delete message from cache by global select", function()
        -- make llm request and trigger cache storage
        local r = proxy_client:post("/llm", {
          headers = {
            ["content-type"] = "application/json",
            ["accept"] = "application/json",
          },
          body = good_request_body,
        })

        assert.res_status(200 , r)
        local x_cache_status = assert.header("X-Cache-Status", r)
        assert.equals("Miss", x_cache_status)

        -- verify it's cached
        wait_until_key_in_cache(vector_connector, "kong_semantic_cache:" .. PLUGIN_ID .. ":*")

        local r = proxy_client:post("/llm", {
          headers = {
            ["content-type"] = "application/json",
            ["accept"] = "application/json",
          },
          body = good_request_body,
        })

        assert.res_status(200 , r)
        local x_cache_status = assert.header("X-Cache-Status", r)
        local x_cache_ttl = assert.header("X-Cache-Ttl", r)
        local x_cache_key = assert.header("X-Cache-Key", r)
        assert.equals("Hit", x_cache_status)
        assert.equals("300", x_cache_ttl)
        assert.equals("kong_semantic_cache", split(x_cache_key, ":")[1])

        -- try to delete it using admin api
        local pret, err = admin_client:delete(fmt("/ai-semantic-cache/%s", x_cache_key))
        assert.is_nil(err)
        assert.equal(204, pret.status)
        
        -- now try to read it back, it should be gone
        local pret, err = admin_client:get(fmt("/ai-semantic-cache/%s", PLUGIN_ID, x_cache_key))
        assert.is_nil(err)
        assert.equal(404, pret.status)
      end)

      it("can delete message from cache by global select", function()
        -- make llm request and trigger cache storage
        local r = proxy_client:post("/llm", {
          headers = {
            ["content-type"] = "application/json",
            ["accept"] = "application/json",
          },
          body = good_request_body,
        })

        assert.res_status(200 , r)
        local x_cache_status = assert.header("X-Cache-Status", r)
        assert.equals("Miss", x_cache_status)

        -- verify it's cached
        wait_until_key_in_cache(vector_connector, "kong_semantic_cache:" .. PLUGIN_ID .. ":*")

        local r = proxy_client:post("/llm", {
          headers = {
            ["content-type"] = "application/json",
            ["accept"] = "application/json",
          },
          body = good_request_body,
        })

        assert.res_status(200 , r)
        local x_cache_status = assert.header("X-Cache-Status", r)
        local x_cache_ttl = assert.header("X-Cache-Ttl", r)
        local x_cache_key = assert.header("X-Cache-Key", r)
        assert.equals("Hit", x_cache_status)
        assert.equals("300", x_cache_ttl)
        assert.equals("kong_semantic_cache", split(x_cache_key, ":")[1])

        -- try to delete it using admin api
        local pret, err = admin_client:delete(fmt("/ai-semantic-cache/%s/caches/%s", PLUGIN_ID, x_cache_key))
        assert.is_nil(err)
        assert.equal(204, pret.status)
        
        -- now try to read it back, it should be gone
        local pret, err = admin_client:get(fmt("/ai-semantic-cache/%s/caches/%s", PLUGIN_ID, x_cache_key))
        assert.is_nil(err)
        assert.equal(404, pret.status)
      end)
    end)
  end)
end -- end for each db_strategy
