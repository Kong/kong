local utils = require "kong.tools.utils"
local cache_key_utils = require "kong.plugins.gql-proxy-cache.cache_key"

describe("builds cache key", function()
  local route1_uuid = utils.uuid()
  local route2_uuid = utils.uuid()

  it("returns cache key in md5 format", function()
    local cache_key = cache_key_utils.build_cache_key(route1_uuid)

    assert.equal(32, #cache_key)
  end)

  it("returns two different cache keys for different routes", function()
    local cache_key1 = cache_key_utils.build_cache_key(route1_uuid)
    local cache_key2 = cache_key_utils.build_cache_key(route2_uuid)

    assert.not_equal(cache_key1, cache_key2)
  end)

  it("returns same keys for same route", function()
    local cache_key1 = cache_key_utils.build_cache_key(route1_uuid)
    local cache_key2 = cache_key_utils.build_cache_key(route1_uuid)

    assert.equal(cache_key1, cache_key2)
  end)

  it("returns same keys for same routes and same body content", function()
    local body_content = '{ query { person(id:"1") { id, name }}}'

    local cache_key1 = cache_key_utils.build_cache_key(route1_uuid, body_content)
    local cache_key2 = cache_key_utils.build_cache_key(route1_uuid, body_content)

    assert.equal(cache_key1, cache_key2)
  end)

  it("returns same keys for same routes, same body content but different body formatting", function()
    local body_content1 = '{ query { person(id:"1") { id, name }}}'
    local body_content2 = '{ query     { person(id:"1") { id,     name   }}}'

    local cache_key1 = cache_key_utils.build_cache_key(route1_uuid, body_content1)
    local cache_key2 = cache_key_utils.build_cache_key(route1_uuid, body_content2)

    assert.equal(cache_key1, cache_key2)
  end)

  it("returns different keys for same routes and different body content", function()
    local body_content1 = '{ query { person(id:"1") { id, name }}}'
    local body_content2 = '{ query { person(id:"2") { id, name }}}'

    local cache_key1 = cache_key_utils.build_cache_key(route1_uuid, body_content1)
    local cache_key2 = cache_key_utils.build_cache_key(route1_uuid, body_content2)

    assert.not_equal(cache_key1, cache_key2)
  end)

  it("returns different keys for different routes and same body content", function()
    local body_content1 = '{ query { person(id:"1") { id, name }}}'

    local cache_key1 = cache_key_utils.build_cache_key(route1_uuid, body_content1)
    local cache_key2 = cache_key_utils.build_cache_key(route2_uuid, body_content1)

    assert.not_equal(cache_key1, cache_key2)
  end)

  it("returns different keys for same routes and different body content", function()
    local body_content1 = '{ query { person(id:"1") { id, name }}}'
    local body_content2 = '{ query { person(id:"2") { id, name }}}'

    local cache_key1 = cache_key_utils.build_cache_key(route1_uuid, body_content1)
    local cache_key2 = cache_key_utils.build_cache_key(route1_uuid, body_content2)

    assert.not_equal(cache_key1, cache_key2)
  end)

  it("returns same keys for same routes, same body contents and same headers", function()
    local body_content1 = '{ query { person(id:"1") { id, name }}}'

    local http_headers = {
      h1 = "h1",
      h2 = "h2"
    }
    local vary_headers = {
      "h1"
    }

    local cache_key1 = cache_key_utils.build_cache_key(route1_uuid, body_content1, http_headers, vary_headers)
    local cache_key2 = cache_key_utils.build_cache_key(route1_uuid, body_content1, http_headers, vary_headers)

    assert.equal(cache_key1, cache_key2)
  end)

  it("returns same keys for same routes, same body contents and different headers with empty vary_headers configuration", function()
    local body_content = '{ query { person(id:"1") { id, name }}}'

    local http_headers = {
      h1 = "h1",
      h2 = "h2"
    }

    local vary_headers = {}

    local cache_key1 = cache_key_utils.build_cache_key(route1_uuid, body_content, http_headers, vary_headers)
    local cache_key2 = cache_key_utils.build_cache_key(route1_uuid, body_content, http_headers, vary_headers)

    assert.equal(cache_key1, cache_key2)
  end)

  it("returns different keys for same routes, same body contents and different headers", function()
    local body_content = '{ query { person(id:"1") { id, name }}}'

    local http_headers1 = {
      h1 = "h1",
      h2 = "h2"
    }

    local http_headers2 = {
      h1 = "h1-2",
      h2 = "h2"
    }

    local vary_headers = {
      "h1"
    }

    local cache_key1 = cache_key_utils.build_cache_key(route1_uuid, body_content, http_headers1, vary_headers)
    local cache_key2 = cache_key_utils.build_cache_key(route1_uuid, body_content, http_headers2, vary_headers)

    assert.not_equal(cache_key1, cache_key2)
  end)
end)
