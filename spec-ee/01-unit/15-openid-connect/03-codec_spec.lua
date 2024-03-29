-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local codec = require "kong.openid-connect.codec"

describe("Test codec", function ()
  local test_str = ""
  for d = 48, 126 do
    test_str = test_str .. string.char(d)
  end

  it("correctly performs json encoding", function ()
    local json = codec.json
    local t = { somekey = "somevalue" }
    local expected = '{"somekey":"somevalue"}'
    assert.equals(expected, json.encode(t))
  end)

  it("correctly performs json decoding", function ()
    local json = codec.json
    local s = '{"somekey":"somevalue","somenumber":123}'
    local expected = { somekey = "somevalue", somenumber = 123 }
    assert.same(expected, json.decode(s))
  end)

  it("correctly performs base16 encoding", function ()
    local base16 = codec.base16
    local s = "some input"
    local expected = "736f6d6520696e707574"
    assert.equals(expected, base16.encode(s))
  end)

  it("correctly performs base16 decoding", function ()
    local base16 = codec.base16
    local s = "736f6d6520696e707574"
    local expected = "some input"
    assert.equals(expected, base16.decode(s))
  end)

  it("fails base16 decoding of invalid input", function ()
    local base16 = codec.base16
    local s = "invalid base16"
    local decoded, err = base16.decode(s)
    assert.is_nil(decoded)
    assert.equals("unable to decode base16 data", err)
  end)

  it("correctly performs base16 encoding and decoding", function ()
    local base16 = codec.base16
    assert.equals(test_str, base16.decode(base16.encode(test_str)))
  end)

  it("correctly performs base64 encoding", function ()
    local base64 = codec.base64
    local s = "some input"
    local expected = "c29tZSBpbnB1dA=="
    assert.equals(expected, base64.encode(s))
  end)

  it("correctly performs base64 decoding", function ()
    local base64 = codec.base64
    local s = "c29tZSBpbnB1dA=="
    local expected = "some input"
    assert.equals(expected, base64.decode(s))
  end)

  it("fails base64 decoding of invalid input", function ()
    local base64 = codec.base64
    local s = "invalid base64"
    local decoded, err = base64.decode(s)
    assert.is_nil(decoded)
    assert.equals("unable to decode base64 data", err)
  end)

  it("correctly performs base64 encoding and decoding", function ()
    local base64 = codec.base64
    assert.equals(test_str, base64.decode(base64.encode(test_str)))
  end)

  it("correctly performs base64url encoding", function ()
    local base64url = codec.base64url
    local s = "<<?!>>!"
    local expected = "PDw_IT4-IQ"
    assert.equals(expected, base64url.encode(s))
  end)

  it("correctly performs base64url decoding", function ()
    local base64url = codec.base64url
    local s = "PDw_IT4-IQ"
    local expected = "<<?!>>!"
    assert.equals(expected, base64url.decode(s))
  end)

  it("fails base64url decoding of invalid input", function ()
    local base64url = codec.base64url
    local s = "invalid base64url"
    local decoded, err = base64url.decode(s)
    assert.is_nil(decoded)
    assert.matches("unable to decode base64url data:", err)
  end)

  it("correctly performs base64url encoding and decoding", function ()
    local base64url = codec.base64url
    assert.equals(test_str, base64url.decode(base64url.encode(test_str)))
  end)

  it("correctly performs basic auth encoding and decoding", function ()
    local credentials = codec.credentials
    local id = "someid"
    local secret = "somesecret"
    local i, s = credentials.decode(credentials.encode(id, secret))

    assert.equals(id, i)
    assert.equals(secret, s)
  end)
end)
