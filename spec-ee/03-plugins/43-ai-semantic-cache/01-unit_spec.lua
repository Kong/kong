-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local PLUGIN_NAME = "ai-semantic-cache"

local samples = {
  ["llm/v1/chat"] = {
    ["valid"] = {
      messages = {
        {
          role = "system",
          content = "You are a mathematician."
        },
        {
          role = "user",
          content = "What is Pi?"
        },
        {
          role = "assistant",
          content = "Pi (π) is a mathematical constant that represents the ratio of a circle's circumference to its diameter. This ratio is constant for all circles and is approximately equal to 3.14159."
        },
        {
          role = "user",
          content = "What is 2π?"
        },
      },
      usage = {
        prompt_tokens = 10,
        completion_tokens = 20,
        total_tokens = 30,
      },
    },
    ["invalid_empty_messages"] = {
      messages = {},
    },
    ["invalid_wrong_format"] = {
      role = "user",
      content = "You are a mathematician, what is Pi?",
    },
  },
}

describe(PLUGIN_NAME .. ": (unit)", function()

  local access_handler

  setup(function()
    _G._TEST = true
    package.loaded["kong.plugins.ai-semantic-cache.handler"] = nil
  end)

  teardown(function()
    _G._TEST = nil
  end)

  before_each(function()
    _G._TEST = true
    package.loaded["kong.plugins.ai-semantic-cache.handler"] = nil
    access_handler = require("kong.plugins.ai-semantic-cache.handler")
  end)

  after_each(function()
    _G._TEST = nil
    access_handler = nil
  end)

  describe("llm/v1/chat operations", function()
    it("test parsing directive header", function()
      -- test null
      assert.same(access_handler._parse_directive_header(nil), {})

      -- test empty string
      assert.same(access_handler._parse_directive_header(""), {})

      -- test string
      assert.same(access_handler._parse_directive_header("cache-key=kong-cache,cache-age=300"), {
        ["cache-age"] = 300,
        ["cache-key"] = "kong-cache",
      })

      -- test table
      assert.same(access_handler._parse_directive_header({
        ["cache-age"] = 300,
        ["cache-key"] = "kong-cache",
      }), {
        ["cache-age"] = 300,
        ["cache-key"] = "kong-cache",
      })
    end)

    it("test good analytics output", function()
      local this_conf, this_stats

      access_handler._set_kong({
        ctx = {
          shared = {
            ai_conf_copy = {
              __key__ = "kong-ai-proxy-1",
              model = {
                provider = "openai",
              },
            },
          },
        },
      })

      access_handler._set_ngx({
        now = function()
          return math.floor(ngx.now()) + 10
        end,
        update_time = function()
          return true
        end,
      })

      access_handler._set_ai_shared({
        post_request = function(conf, stats)
          this_conf = conf
          this_stats = stats
        end,
      })
      
      access_handler._send_stats({
        vectordb = {
          driver = "redis",
        },
        embeddings = {
          driver = "redis",
          model = "kong-model",
        },
      }, samples["llm/v1/chat"]["valid"], nil, math.floor(ngx.now()), 100)

      assert.same(this_conf, {
        __key__ = "kong-ai-proxy-1",
        model = {
          provider = "openai",
        },
      })

      this_stats.messages = nil  -- wipe the message context save
      assert.same(this_stats, {
        usage = {
          prompt_tokens = 10,
          completion_tokens = 20,
          total_tokens = 30,
        },
        cache = {
          vector_db = "redis",
          embeddings_latency = 100000,
          embeddings_provider = "redis",
          embeddings_model = "kong-model",
          fetch_latency = 10000,
        }
      })
    end)

    it("test error analytics output", function()
      local this_conf, this_stats

      access_handler._set_kong({
        ctx = {
          shared = {
            ai_conf_copy = "ai_conf_copy",
          },
        },
      })
      access_handler._set_ai_shared({
        post_request = function(conf, stats)
          this_conf = conf
          this_stats = stats
        end,
      })

      access_handler._send_stats_error({
        vectordb = {
          driver = "kong_vectordb",
        },
        embeddings = {
          driver = "kong_embeddings",
          model = "kong_model",
        },
      }, "KONG_ERROR")

      assert.same(this_conf, "ai_conf_copy")
      assert.same(this_stats, {
        usage = {
          prompt_tokens = 0,
          completion_tokens = 0,
          total_tokens = 0,
        },
        cache = {
          vector_db = "kong_vectordb",
          embeddings_provider = "kong_embeddings",
          embeddings_model = "kong_model",
          cache_status = "KONG_ERROR",
        }
      })
    end)

    it("test message format recognition and validation", function()
      assert.is_truthy(access_handler._validate_incoming(samples["llm/v1/chat"]["valid"]))
      assert.is_falsy(access_handler._validate_incoming(samples["llm/v1/chat"]["invalid_empty_messages"]))
      assert.is_falsy(access_handler._validate_incoming(samples["llm/v1/chat"]["invalid_wrong_format"]))
    end)

    it("test ttl calculation", function()
      -- test max-age header
      access_handler._set_ngx({
        var = {
          sent_http_expires = "60",
        },
      })
      local access_control_header = access_handler._parse_directive_header("cache-key=kong-cache,max-age=300")

      assert.same(access_handler._resource_ttl(access_control_header), 300)

      -- test s-maxage header
      access_handler._set_ngx({
        var = {
          sent_http_expires = "60",
        },
      })
      local access_control_header = access_handler._parse_directive_header("cache-key=kong-cache,s-maxage=310")

      assert.same(access_handler._resource_ttl(access_control_header), 310)

      -- test empty headers
      local expiry_year = os.date("%Y") + 1
      access_handler._set_ngx({
        var = {
          sent_http_expires = os.date("!%a, %d %b ") .. expiry_year .. " " .. os.date("!%X GMT")  -- format: "Thu, 18 Nov 2099 11:27:35 GMT",
        },
      })

      -- chop the last digit to avoid flaky tests (clock skew)
      assert.same(string.sub(access_handler._resource_ttl(), 0, -2), "3153600")
    end)

    it("test chat truncation", function()
      local output
      
      -- test truncate to two messages
      output = access_handler._format_chat(samples["llm/v1/chat"]["valid"]["messages"], 2, false, false)
      assert.same(output, 'What is Pi?\n\nsystem: You are a mathematician.\n\n')
      
      -- test discard system messages
      output = access_handler._format_chat(samples["llm/v1/chat"]["valid"]["messages"], 20, true, false)
      assert.same(output, 'What is 2π?\n\nassistant: Pi (π) is a mathematical constant that represents the ratio of a circle\'s circumference to its diameter. This ratio is constant for all circles and is approximately equal to 3.14159.\n\nWhat is Pi?\n\n')

      -- test discard assistant messages
      output = access_handler._format_chat(samples["llm/v1/chat"]["valid"]["messages"], 20, false, true)
      assert.same(output, 'What is 2π?\n\nWhat is Pi?\n\nsystem: You are a mathematician.\n\n')
    end)

  end)
end)
