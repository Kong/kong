-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local llm_class = require("kong.llm")
local helpers = require "spec.helpers"
local cjson = require "cjson"

local MOCK_PORT = 62349
local PLUGIN_NAME = "ai-response-transformer"

local OPENAI_INSTRUCTIONAL_RESPONSE = {
  route_type = "llm/v1/chat",
  model = {
    name = "gpt-4",
    provider = "openai",
    options = {
      max_tokens = 512,
      temperature = 0.5,
      upstream_url = "http://"..helpers.mock_upstream_host..":"..MOCK_PORT.."/instructions"
    },
  },
  auth = {
    header_name = "Authorization",
    header_value = "Bearer openai-key",
  },
}

local REQUEST_BODY = [[
  {
    "persons": [
      {
        "name": "Kong A",
        "age": 31
      },
      {
        "name": "Kong B",
        "age": 42
      }
    ]
  }
]]

local EXPECTED_RESULT = {
  body = [[<persons>
  <person>
    <name>Kong A</name>
    <age>62</age>
  </person>
  <person>
    <name>Kong B</name>
    <age>84</age>
  </person>
</persons>]],
  status = 209,
  headers = {
    ["content-type"] = "application/xml",
  },
}

local SYSTEM_PROMPT = "You are a mathematician. "
                   .. "Multiply all numbers in my JSON request, by 2. Return me this message: "
                   .. "{\"status\": 400, \"headers: {\"content-type\": \"application/xml\"}, \"body\": \"OUTPUT\"} "
                   .. "where 'OUTPUT' is the result but transformed into XML format."


local client


for _, strategy in helpers.all_strategies() do if strategy ~= "cassandra" then

  describe(PLUGIN_NAME .. ": (unit)", function()

    lazy_setup(function()
      -- set up provider fixtures
      local fixtures = {
        http_mock = {},
      }

      fixtures.http_mock.openai = [[
        server {
            server_name llm;
            listen ]]..MOCK_PORT..[[;
            
            default_type 'application/json';

            location ~/instructions {
              content_by_lua_block {
                local pl_file = require "pl.file"
                ngx.print(pl_file.read("spec/fixtures/ai-proxy/openai/request-transformer/response-with-instructions.json"))
              }
            }
        }
      ]]

      -- start kong
      assert(helpers.start_kong({
        -- set the strategy
        database   = strategy,
        -- use the custom test template to create a local mock server
        nginx_conf = "spec/fixtures/custom_nginx.template",
        -- make sure our plugin gets loaded
        plugins = "bundled," .. PLUGIN_NAME,
        -- write & load declarative config, only if 'strategy=off'
        declarative_config = strategy == "off" and helpers.make_yaml_file() or nil,
      }, nil, nil, fixtures))
    end)
    
    lazy_teardown(function()
      helpers.stop_kong(nil, true)
    end)

    before_each(function()
      client = helpers.proxy_client()
    end)

    after_each(function()
      if client then client:close() end
    end)

    describe("openai transformer tests, specific response", function()
      it("transforms request based on LLM instructions, with response transformation instructions format", function()
        local llm = llm_class:new(OPENAI_INSTRUCTIONAL_RESPONSE, {})
        assert.truthy(llm)

        local result, err = llm:ai_introspect_body(
          REQUEST_BODY,  -- request body
          SYSTEM_PROMPT, -- conf.prompt
          {},            -- http opts
          nil            -- transformation extraction pattern (loose json)
        )

        assert.is_nil(err)

        local table_result, err = cjson.decode(result)
        assert.is_nil(err)
        assert.same(EXPECTED_RESULT, table_result)

        -- parse in response string format
        local headers, body, status, err = llm:parse_json_instructions(result)
        assert.is_nil(err)
        assert.same({ ["content-type"] = "application/xml"}, headers)
        assert.same(209, status)
        assert.same(EXPECTED_RESULT.body, body)

        -- parse in response table format
        headers, body, status, err = llm:parse_json_instructions(table_result)
        assert.is_nil(err)
        assert.same({ ["content-type"] = "application/xml"}, headers)
        assert.same(209, status)
        assert.same(EXPECTED_RESULT.body, body)
      end)

    end)
  end)
end end
