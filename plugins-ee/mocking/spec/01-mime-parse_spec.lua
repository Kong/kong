-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local mime_parse = require "kong.plugins.mocking.mime_parse"

local best_match = mime_parse.best_match

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

end)
