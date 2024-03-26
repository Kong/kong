local llm_class = require("kong.llm")
local helpers = require "spec.helpers"
local cjson = require "cjson"
local http_mock = require "spec.helpers.http_mock"
local pl_path = require "pl.path"

local MOCK_PORT = helpers.get_available_port()
local PLUGIN_NAME = "ai-response-transformer"

local OPENAI_INSTRUCTIONAL_RESPONSE = {
  route_type = "llm/v1/chat",
  model = {
    name = "gpt-4",
    provider = "openai",
    options = {
      max_tokens = 512,
      temperature = 0.5,
      upstream_url = "http://" .. helpers.mock_upstream_host .. ":" .. MOCK_PORT .. "/instructions"
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


describe(PLUGIN_NAME .. ": (unit)", function()
  local mock
  local mock_response_file = pl_path.abspath(
    "spec/fixtures/ai-proxy/openai/request-transformer/response-with-instructions.json")

  lazy_setup(function()
    mock = http_mock.new(tostring(MOCK_PORT), {
      ["/instructions"] = {
        content = string.format([[
            local pl_file = require "pl.file"
            ngx.header["Content-Type"] = "application/json"
            ngx.say(pl_file.read("%s"))
          ]], mock_response_file),
      },
    }, {
      hostname = "llm",
    })

    assert(mock:start())
  end)

  lazy_teardown(function()
    assert(mock:stop())
  end)

  describe("openai transformer tests, specific response", function()
    it("transforms request based on LLM instructions, with response transformation instructions format", function()
      local llm = llm_class:new(OPENAI_INSTRUCTIONAL_RESPONSE, {})
      assert.truthy(llm)

      local result, err = llm:ai_introspect_body(
        REQUEST_BODY,      -- request body
        SYSTEM_PROMPT,     -- conf.prompt
        {},                -- http opts
        nil                -- transformation extraction pattern (loose json)
      )

      assert.is_nil(err)

      local table_result, err = cjson.decode(result)
      assert.is_nil(err)
      assert.same(EXPECTED_RESULT, table_result)

      -- parse in response string format
      local headers, body, status, err = llm:parse_json_instructions(result)
      assert.is_nil(err)
      assert.same({ ["content-type"] = "application/xml" }, headers)
      assert.same(209, status)
      assert.same(EXPECTED_RESULT.body, body)

      -- parse in response table format
      headers, body, status, err = llm:parse_json_instructions(table_result)
      assert.is_nil(err)
      assert.same({ ["content-type"] = "application/xml" }, headers)
      assert.same(209, status)
      assert.same(EXPECTED_RESULT.body, body)
    end)
  end)
end)
