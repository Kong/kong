local mime_type = require "kong.tools.mime_type"

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
        local type, subtype, params = mime_type.parse_mime_type(case.mime_type)
        local result = { type = type, subtype = subtype, params = params }
        assert.same(case.result, result, "case: " .. i .. " failed" )
      end
    end)
  end)

  describe("includes()", function()
    it("sanity", function()
      local media_types = {
        all = { type = "*", subtype = "*" },
        text_plain = { type = "text", subtype = "plain" },
        text_all = { type = "text", subtype = "*" },
        application_soap_xml = { type = "application", subtype = "soap+xml" },
        application_wildcard_xml = { type = "application", subtype = "*+xml" },
        suffix_xml = { type = "application", subtype = "x.y+z+xml" },
        application_json = { type = "application", subtype = "json" },
      }

      local cases = {
        {
          this = media_types.text_plain,
          other = media_types.text_plain,
          result = true,
        },
        {
          this = media_types.text_all,
          other = media_types.text_plain,
          result = true,
        },
        {
          this = media_types.text_plain,
          other = media_types.text_all,
          result = false,
        },
        {
          this = media_types.all,
          other = media_types.text_plain,
          result = true,
        },
        {
          this = media_types.text_plain,
          other = media_types.all,
          result = false,
        },
        {
          this = media_types.application_soap_xml,
          other = media_types.application_soap_xml,
          result = true,
        },
        {
          this = media_types.application_wildcard_xml,
          other = media_types.application_wildcard_xml,
          result = true,
        },
        {
          this = media_types.application_wildcard_xml,
          other = media_types.suffix_xml,
          result = true,
        },
        {
          this = media_types.application_wildcard_xml,
          other = media_types.application_soap_xml,
          result = true,
        },
        {
          this = media_types.application_soap_xml,
          other = media_types.application_wildcard_xml,
          result = false,
        },
        {
          this = media_types.suffix_xml,
          other = media_types.application_wildcard_xml,
          result = false,
        },
        {
          this = media_types.application_wildcard_xml,
          other = media_types.application_json,
          result = false,
        },
      }

      for i, case in ipairs(cases) do
        assert.is_true(mime_type.includes(case.this, case.other) == case.result, "case: " .. i .. " failed" )
      end
    end)

    it("throws an error for invalid arguments", function()
      assert.has_error(function() mime_type.includes(nil, {})  end, "this must be a table")
      assert.has_error(function() mime_type.includes({}, nil)  end, "other must be a table")
    end)
  end)

end)
