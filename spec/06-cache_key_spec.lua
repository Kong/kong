local helpers = require "spec.helpers"
local cjson = require "cjson"
local rbac = require "kong.rbac"
local utils = require "kong.tools.utils"
local key_utils = require "kong.plugins.proxy-cache.cache_key"


describe("params_key", function()
  it("defaults to all", function()
    assert.equal("a=1:b=2", key_utils.params_key({a = 1, b = 2},{}))
  end)

  it("empty query_string returns empty", function()
    assert.equal("", key_utils.params_key({},{}))
  end)

  it("empty query_string returns empty with vary query_params", function()
    assert.equal("", key_utils.params_key({},{"a"}))
  end)

  it("sorts the arguments", function()
    for i = 1, 100 do
      local s1 = "a" .. utils.random_string()
      local s2 = "b" .. utils.random_string()
      assert.equal(s1.."=1:".. s2 .. "=2", key_utils.params_key({[s2] = 2, [s1] = 1},{}))
    end
  end)

  it("uses only params specified in vary", function()
    assert.equal("a=1", key_utils.params_key({a = 1, b = 2},
                   {vary_query_params = {"a"}}))
  end)

  it("deals with multiple params with same name", function()
    assert.equal("a=1,2", key_utils.params_key({a = {1, 2}},
                   {vary_query_params = {"a"}}))
    end)

  it("deals with multiple params with same name and sorts", function()
    assert.equal("a=1,2", key_utils.params_key({a = {2, 1}},
                   {vary_query_params = {"a"}}))
    end)

  it("discards params in config that are not in the request", function()
    assert.equal("a=1,2:b=2", key_utils.params_key({a = {1, 2}, b = 2},
                   {vary_query_params = {"a", "b", "c"}}))
    end)
end)

describe("headers_key", function()
  it("defaults to none", function()
    assert.equal("", key_utils.headers_key({a = 1, b = 2},{}))
  end)

  it("sorts the arguments", function()
    for i = 1, 100 do
      local s1 = "a" .. utils.random_string()
      local s2 = "b" .. utils.random_string()
      assert.equal(s1.."=1:".. s2 .. "=2", key_utils.params_key({[s2] = 2, [s1] = 1},
                     {vary_headers = {"a", "b"}}))
    end
  end)

  it("uses only params specified in vary", function()
    assert.equal("a=1", key_utils.headers_key({a = 1, b = 2},
                   {vary_headers = {"a"}}))
  end)

  it("deals with multiple params with same name", function()
    assert.equal("a=1,2", key_utils.headers_key({a = {1, 2}},
                   {vary_headers = {"a"}}))
    end)

  it("deals with multiple params with same name and sorts", function()
    assert.equal("a=1,2", key_utils.headers_key({a = {2, 1}},
                   {vary_headers = {"a"}}))
    end)

  it("discards params in config that are not in the request", function()
    assert.equal("a=1,2:b=2", key_utils.headers_key({a = {1, 2}, b = 2},
                   {vary_headers = {"a", "b", "c"}}))
  end)
end)
