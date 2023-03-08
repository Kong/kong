local parse_mime_type = require "kong.tools.mime_type".parse_mime_type

describe("kong.tools.mime_type", function()
  describe("parse_mime_type()", function()
    it("sanity", function()
      local cases = {
        {
          -- sanity
          mime_type = "application/json",
          result = { type = "application", subtype = "json", params = {} }
        },
        {
          -- single parameter
          mime_type = "application/json; charset=UTF-8",
          result = { type = "application", subtype = "json", params = { charset = "UTF-8" } }
        },
        {
          -- multiple parameters
          mime_type = "application/json; charset=UTF-8; key=Value; q=1",
          result = { type = "application", subtype = "json", params = { charset = "UTF-8", key = "Value", q = "1" } }
        },
        {
          -- malformed whitespace
          mime_type = "application/json ;  charset=UTF-8 ; key=Value",
          result = { type = "application", subtype = "json", params = { charset = "UTF-8", key = "Value" } }
        },
        {
          -- quote parameter value
          mime_type = 'application/json; charset="UTF-8"',
          result = { type = "application", subtype = "json", params = { charset = "UTF-8" } }
        },
        {
          -- type, subtype and parameter names are case-insensitive
          mime_type = "Application/JSON; Charset=UTF-8; Key=Value",
          result = { type = "application", subtype = "json", params = { charset = "UTF-8", key = "Value" } }
        },
        {
          mime_type = "*/*; charset=UTF-8; q=0.1",
          result = { type = "*", subtype = "*", params = { charset = "UTF-8", q = "0.1" } }
        },
        {
          mime_type = "application/*",
          result = { type = "application", subtype = "*", params = {} }
        },
        {
          mime_type = "*/text",
          result = { type = "*", subtype = "text", params = {} }
        },
        {
          mime_type = "*",
          result = { type = "*", subtype = "*", params = {} }
        },
        {
          mime_type = "*; q=.2",
          result = { type = "*", subtype = "*", params = { q = '.2' } }
        },
        {
          -- invalid input
          mime_type = "helloworld",
          result = { type = nil, subtype = nil, params = nil }
        },
        {
          -- invalid input
          mime_type = " ",
          result = { type = nil, subtype = nil, params = nil }
        },
        {
          -- invalid input
          mime_type = "application/json;",
          result = { type = nil, subtype = nil, params = nil }
        }
      }
      for i, case in ipairs(cases) do
        local type, subtype, params = parse_mime_type(case.mime_type)
        local result = { type = type, subtype = subtype, params = params }
        assert.same(case.result, result, "case: " .. i .. " failed" )
      end
    end)
  end)

end)
