describe("Balancer", function()
  local old_ngx = _G.ngx
  local singletons, resolver
  local UPSTREAMS_FIXTURES

  setup(function()
    --[[local stubbed_ngx = {
      header = {},
      shared = require "spec.fixtures.shm-stub",
      say = function() end,  -- not required as stub, but to prevent outputting to stdout
      req = {
        get_headers = function() return {} end,
        set_header = function() return {} end,
      }
    }
    _G.ngx = setmetatable(stubbed_ngx, {__index = old_ngx})
--]]
    balancer = require "kong.core.balancer"
    singletons = require "kong.singletons"
    singletons.dao = {
      upstreams = {
        find_all = function()
          return UPSTREAMS_FIXTURES
        end
      }
    }

    UPSTREAMS_FIXTURES = {
      {name = "mashape", slots = 10, orderlist = {1,2,3,4,5,6,7,8,9,10} },
      {name = "kong",    slots = 10, orderlist = {10,9,8,7,6,5,4,3,2,1} },
      {name = "gelato",  slots = 10, orderlist = {1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20} },
      {name = "galileo", slots = 10, orderlist = {20,19,18,17,16,15,14,13,12,11,10,9,8,7,6,5,4,3,2,1} },
    }
  end)

  describe("load_upstreams_in_memory()", function()
    local upstreams_dics
    setup(function()
      upstreams_dics = resolver.load_upstreams_in_memory()
    end)

    it("should retrieve all upstreams in datastore", function()
      assert.equal("table", type(apis_dics))
      assert.truthy(apis_dics.by_dns)
      assert.truthy(apis_dics.request_path_arr)
      assert.truthy(apis_dics.wildcard_dns_arr)
    end)
    it("should return a dictionary of APIs by request_host", function()
      assert.equal("table", type(apis_dics.by_dns["mockbin.com"]))
      assert.equal("table", type(apis_dics.by_dns["mockbin-auth.com"]))
    end)
    it("should return an array of APIs by request_path", function()
      assert.equal("table", type(apis_dics.request_path_arr))
      assert.equal(7, #apis_dics.request_path_arr)
      for _, item in ipairs(apis_dics.request_path_arr) do
        assert.truthy(item.strip_request_path_pattern)
        assert.truthy(item.request_path)
        assert.truthy(item.api)
      end
      assert.equal("/strip%-me", apis_dics.request_path_arr[1].strip_request_path_pattern)
      assert.equal("/strip", apis_dics.request_path_arr[2].strip_request_path_pattern)
    end)
    it("should return an array of APIs with wildcard request_host", function()
      assert.equal("table", type(apis_dics.wildcard_dns_arr))
      assert.equal(2, #apis_dics.wildcard_dns_arr)
      for _, item in ipairs(apis_dics.wildcard_dns_arr) do
        assert.truthy(item.api)
        assert.truthy(item.pattern)
      end
      assert.equal("^.+%.wildcard%.com$", apis_dics.wildcard_dns_arr[1].pattern)
      assert.equal("^wildcard%..+$", apis_dics.wildcard_dns_arr[2].pattern)
    end)
  end)
