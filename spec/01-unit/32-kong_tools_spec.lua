-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local http = require "kong.tools.http"

describe("http", function()
    it("test parse_directive_header function", function()
      -- test null
      assert.same(http.parse_directive_header(nil), {})

      -- test empty string
      assert.same(http.parse_directive_header(""), {})

      -- test string
      assert.same(http.parse_directive_header("cache-key=kong-cache,cache-age=300"), {
        ["cache-age"] = 300,
        ["cache-key"] = "kong-cache",
      })
    end)

    it("test calculate_resource_ttl function", function()
      -- test max-age header
      _G.ngx = {
        var = {
          sent_http_expires = "60",
        },
      }
      local access_control_header = http.parse_directive_header("cache-key=kong-cache,max-age=300")

      assert.same(http.calculate_resource_ttl(access_control_header), 300)

      -- test s-maxage header
      _G.ngx = {
        var = {
          sent_http_expires = "60",
        },
      }
      local access_control_header = http.parse_directive_header("cache-key=kong-cache,s-maxage=310")

      assert.same(http.calculate_resource_ttl(access_control_header), 310)

      -- test empty headers
      local expiry_year = os.date("%Y") + 1
      _G.ngx = {
        var = {
          sent_http_expires = os.date("!%a, %d %b ") .. expiry_year .. " " .. os.date("!%X GMT")  -- format: "Thu, 18 Nov 2099 11:27:35 GMT",
        },
      }

      -- chop the last digit to avoid flaky tests (clock skew)
      assert.same(string.sub(http.calculate_resource_ttl(), 0, -2), "3153600")
    end)
end)