require("spec.helpers") -- for kong.log
local declarative = require "kong.db.declarative"
local conf_loader = require "kong.conf_loader"

local null = ngx.null


describe("declarative", function()
  describe("parse_string", function()
    it("converts lyaml.null to ngx.null", function()
      local dc = declarative.new_config(conf_loader())
      local entities, err = dc:parse_string [[
_format_version: "1.1"
routes:
  - name: null
    paths:
    - /
]]
      assert.equal(nil, err)
      local _, route = next(entities.routes)
      assert.equal(null,   route.name)
      assert.same({ "/" }, route.paths)
    end)
  end)

  it("ttl fields are accepted in DB-less schema validation", function()
    local dc = declarative.new_config(conf_loader())
    local entities, err = dc:parse_string([[
_format_version: '2.1'
consumers:
- custom_id: ~
  id: e150d090-4d53-4e55-bff8-efaaccd34ec4
  tags: ~
  username: bar@example.com
services:
keyauth_credentials:
- created_at: 1593624542
  id: 3f9066ef-b91b-4d1d-a05a-28619401c1ad
  tags: ~
  ttl: ~
  key: test
  consumer: e150d090-4d53-4e55-bff8-efaaccd34ec4
]])
    assert.equal(nil, err)

    assert.is_nil(entities.keyauth_credentials['3f9066ef-b91b-4d1d-a05a-28619401c1ad'].ttl)
  end)

  describe("unique_field_key()", function()
    local unique_field_key = declarative.unique_field_key
    local sha256_hex = require("kong.tools.sha256").sha256_hex

    it("utilizes the schema name, workspace id, field name, and checksum of the field value", function()
      local key = unique_field_key("services", "123", "fieldname", "test", false)
      assert.is_string(key)
      assert.equals("U|services|fieldname|123|" .. sha256_hex("test"), key)
    end)

    -- since rpc sync the param `unique_across_ws` is useless
    -- this test case is just for compatibility
    it("does not omits the workspace id when 'unique_across_ws' is 'true'", function()
      local key = unique_field_key("services", "123", "fieldname", "test", true)
      assert.equals("U|services|fieldname|123|" .. sha256_hex("test"), key)
    end)
  end)

  it("parse nested entity correctly", function ()
    local dc = declarative.new_config(conf_loader())
    local entities, err = dc:parse_string([[{"_format_version": "3.0","consumers": [{"username": "consumerA","basicauth_credentials": [{"username": "qwerty","password": "qwerty"}]}],"certificates": [{"id": "eab647a0-314a-4c26-94ec-3e9d78e4293f","cert": "-----BEGIN CERTIFICATE-----\nMIIDzTCCArWgAwIBAgIUMmq4W4is+P02LXKinUdLoPjFuDYwDQYJKoZIhvcNAQEL\nBQAwdjELMAkGA1UEBhMCVVMxEzARBgNVBAgMCkNhbGlmb3JuaWExFjAUBgNVBAcM\nDVNhbiBGcmFuY2lzY28xIDAeBgNVBAoMF0tvbmcgQ2x1c3RlcmluZyBUZXN0aW5n\nMRgwFgYDVQQDDA9rb25nX2NsdXN0ZXJpbmcwHhcNMTkxMTEzMDU0NTA1WhcNMjkx\nMTEwMDU0NTA1WjB2MQswCQYDVQQGEwJVUzETMBEGA1UECAwKQ2FsaWZvcm5pYTEW\nMBQGA1UEBwwNU2FuIEZyYW5jaXNjbzEgMB4GA1UECgwXS29uZyBDbHVzdGVyaW5n\nIFRlc3RpbmcxGDAWBgNVBAMMD2tvbmdfY2x1c3RlcmluZzCCASIwDQYJKoZIhvcN\nAQEBBQADggEPADCCAQoCggEBALr7evXK3nLxW98lXDWUcyNRCKDzUVX5Rlm7ny0a\nqVIh+qRUT7XGHFnDznl7s1gEkcxLtuMnKBV7Ic2jVTzKluZZFJD5H2plP7flpVu/\nbyvpBNguERFDC2mbnlX7TSRhhWjlYTgFS2KiFP1OjYjim6vemszobDsCg2gRs0Mh\nA7XwsVvPSFNfnAOPTpyLRGtN3ShEA0LKjBkjg2u67MPAfg1y8/8Tm3h/kqfOciMT\n5ax2J1Ll/9/oCWX9qW6gNmnnUGNlBpcAZk3pzh6n1coRnVaysoCPYPgd9u1KoBkt\nuTQJOn1Qi3OWPZzyiLGRa/X0tGx/5QQDnLr6GyDjwPcC09sCAwEAAaNTMFEwHQYD\nVR0OBBYEFNNvhlhHAsJtBZejHystlPa/CoP2MB8GA1UdIwQYMBaAFNNvhlhHAsJt\nBZejHystlPa/CoP2MA8GA1UdEwEB/wQFMAMBAf8wDQYJKoZIhvcNAQELBQADggEB\nAHQpVBYGfFPFTRY/HvtWdXROgW358m9rUC5E4SfTJ8JLWpCB4J+hfjQ+mASTFb1V\n5FS8in8S/u1MgeU65RC1/xt6Rof7Tu/Cx2SusPWo0YGyN0E9mwr2c91JsIgDO03Y\ngtDiavyw3tAPVo5n2U3y5Hf46bfT5TLZ2yFnUJcKRZ0CeX6YAJA5dwG182xOn02r\nkkh9T1bO72pQHi15QxnQ9Gc4Mi5gjuxX4/Xyag5KyEXnniTb7XquW+JKP36RfhnU\nDGoEEUNU5UYwIzh910NM0UZubu5Umya1JVumoDqAi1lf2DHhKwDNAhmozYqE1vJJ\n+e1C9/9oqok3CRyLDe+VJ7M=\n-----END CERTIFICATE-----\n","key": "-----BEGIN PRIVATE KEY-----\nMIIEvgIBADANBgkqhkiG9w0BAQEFAASCBKgwggSkAgEAAoIBAQC6+3r1yt5y8Vvf\nJVw1lHMjUQig81FV+UZZu58tGqlSIfqkVE+1xhxZw855e7NYBJHMS7bjJygVeyHN\no1U8ypbmWRSQ+R9qZT+35aVbv28r6QTYLhERQwtpm55V+00kYYVo5WE4BUtiohT9\nTo2I4pur3prM6Gw7AoNoEbNDIQO18LFbz0hTX5wDj06ci0RrTd0oRANCyowZI4Nr\nuuzDwH4NcvP/E5t4f5KnznIjE+WsdidS5f/f6All/aluoDZp51BjZQaXAGZN6c4e\np9XKEZ1WsrKAj2D4HfbtSqAZLbk0CTp9UItzlj2c8oixkWv19LRsf+UEA5y6+hsg\n48D3AtPbAgMBAAECggEBALoFVt8RZR2VYYEu+f2UIrgP9jWp3FFcHdFIB6Qn0iwU\nAfdaqbJ91da4JsJVfqciZKqK6Pg0DHzSc17SEArawiWImh1guxBuimW54jjUyxU0\nTc2EhxZVTRVT7MI9sRFws/kXuxCws7784UTg0Y5NY/IpFHinAoXyiikO8vjl73sg\ntrN5mQGNTE/c8lEs7pUAFWX9zuNbmV0m1q25lHDgbkAD76/9X26lLCK1A5e2iCj3\nMME6/2GlSy3hrtSY7mCiR1GktvnK+yidXXJSkGMNCSopQARfcAlMvcCDav5ODxTz\nmB+A47oxGKBTdc9gGF44dR15y5E1kRAvTtaAIzpc14ECgYEA4u9uZkZS0gEiiA5K\npOm/lnBp6bloGg9RlsOO5waE8DiGZgkwWuDwsncxUB1SvLd28MgxZzNQClncS98J\nviJzdAVzauMpn3Iqrdtk9drGzEeuxibic1FKMf1URGwKnlcsDHaeKAGyRQgO2Q7l\nOy7EwtRmUKBUA3RCIqLSoiEi6NcCgYEA0u4a2abgYdyR1QMavgevqCGhuqu1Aa2Y\nrbD3TmIfGVubI2YZeFSyhC/7Jx+5HofQj5cpMRgASxzKXqrCXuyb+Q+u23kHogfQ\ncO1yO2GzjlA3FVHTK28t9EDPTOgHWQt3q7iS1s44VHwXDOpEQJ2onKKohvcP5WTf\nLO0T2K9NOJ0CgYEAtX9nHXc6/+iWdJhxjKnCaBBqNNrrboQ37ctj/FOTeQjMPMk2\nmkhzWVjI4NlC9doJz5NdJ7u7VTv/W9L7WMz256EAaUlbXcGSbtAcVCFwg6sFFke9\nLxuhqo+AmOSMLY1sll88KKUKrfk+3szx+z5xcZ0sY2mHJ+gQiOEOc0rrP6sCgYBi\nKsi6RU0mnoYMki5PBLq+0DA59ZH/XvCw3ayrgUUiAx1XwzvVYe3XUZFc6wm36NOr\nEFnubFIuow6YMnbVwN7yclcZ8+EWivZ6qDfC5Tyw3ipUtMlH7K2BgOw5yb8ptQmU\nFQnaCQ30W/BKZXkwbW+8voMalT+DroejnA7hiOyyjQKBgFLi6x6w76fTgQ7Ts8x0\neATLOrvdvfotuLyMSsQLbljXyJznCTNrOGfYTua/Ifgkn4LpnoOkkxvVbj/Eugc7\nWeXBG+gbEi25GZUktrZWP1uc6s8aXH6rjYJP8iXnUpFHmQAPGuGiFnfB5MxlSns9\n9SKBXe7AvKGknGf7zg8WLKJZ\n-----END PRIVATE KEY-----\n","snis": [{"name": "alpha.example","id": "c6ac927c-4f5a-4e88-8b5d-c7b01d0f43af"}]}]}]])

    assert.is_nil(err)
    assert.is_table(entities)
    assert.is_not_nil(entities.snis)
    assert.same('alpha.example', entities.certificates['eab647a0-314a-4c26-94ec-3e9d78e4293f'].snis[1].name)
  end)

end)
