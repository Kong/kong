-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local mime_parse = require "kong.plugins.mocking.mime_parse"
local stringx = require "pl.stringx"

local split = stringx.split

local best_match = mime_parse.best_match
local compute_score = mime_parse._compute_score
local parse_media_range = mime_parse._parse_media_range

describe("MIME parse tests", function()

  it("simple test case", function()
    local supported_mime_types = { "application/json", "application/xml", "text/plain" }

    assert.equal(best_match(supported_mime_types, "application/json"), "application/json")
    assert.equal(best_match(supported_mime_types, "application/xml"), "application/xml")
    assert.equal(best_match(supported_mime_types, "application/json, application/xml"), "application/json")
    assert.equal(best_match(supported_mime_types, "text/html, application/json, application/xml"), "application/json")
    assert.equal(best_match(supported_mime_types, "text/*, application/json, application/xml"), "application/json")
    assert.equal(best_match(supported_mime_types, "text/html"), "")
  end)

  it("wildcard test case", function()
    local supported_mime_types = { "application/json", "application/xml", "text/plain" }

    assert.equal(best_match(supported_mime_types, "application/*"), "application/json")
    assert.equal(best_match(supported_mime_types, "text/*"), "text/plain")
    assert.equal(best_match(supported_mime_types, "*/*"), "application/json")
    assert.equal(best_match(supported_mime_types, "*"), "application/json")
  end)


  it("quality value test case", function()
    local supported_mime_types = { "application/json", "application/xml", "text/plain" }

    assert.equal(best_match(supported_mime_types, "text/*;q=0.5, *;q=0.1"), "text/plain")
    assert.equal(best_match(supported_mime_types, "application/json;q=0.1, application/xml;q=0.2"), "application/xml")
    assert.equal(best_match(supported_mime_types, "text/a;q=0.1, text/b;q=0.2, *;q=0.3"), "application/json")
    assert.equal(best_match(supported_mime_types, "mock/a;q=0.1, *;q=0.3"), "application/json")
    assert.equal(best_match(supported_mime_types, "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,/;q=0.8,application/signed-exchange;v=b3;q=0.9"), "application/xml")
    assert.equal(best_match(supported_mime_types, "text/*;q=0.8, */xml;q=0.8"), "text/plain")
  end)

  it("abnormal accept header test case", function()
    local supported_mime_types = { "application/json", "application/xml", "text/plain" }

    assert.equal(best_match(supported_mime_types, "application/"), "")
    assert.equal(best_match(supported_mime_types, "*/xml"), "application/xml")
    assert.equal(best_match(supported_mime_types, "text/*;q=0.5,*; q=0.1"), "text/plain")
    assert.equal(best_match(supported_mime_types, "text/*;q=0.5, ;q=1"), "text/plain")
    assert.equal(best_match(supported_mime_types, "application/xml;q=0.5, application/json;q=1.1"), "application/json")
    assert.equal(best_match(supported_mime_types, "application/xml;q=0.5, application/json;q=-0.1"), "application/json")
  end)

  it("compute_score test case", function()
    local accept = "a/b;q=0.9, html/text;q=0.8, text/*;q=0.8, */*;q=0.8"

    local parse_range_list = {}
    local ranges = split(accept, ",")
    for _, range in ipairs(ranges) do
      table.insert(parse_range_list, parse_media_range(range))
    end

    local supported_mime_types_with_score = {
      { type = "a/b", score = 110.9 },
      { type = "html/text", score = 110.8 },
      { type = "text/plain", score = 100.8 },
      { type = "application/json", score = 0.8 },
      { type = "application/xml", score = 0.8 },
    }
    for _, t in ipairs(supported_mime_types_with_score) do
      local score = compute_score(t.type, parse_range_list)
      assert.equal(t.score, score)
    end
  end)

end)
