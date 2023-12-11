-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local certificate = require "kong.runloop.certificate"
local produce_wild_snis = certificate.produce_wild_snis
local match = require "luassert.match"
local sha256_hex = require "kong.tools.sha256".sha256_hex
local uuid = require "kong.tools.utils".uuid


describe("kong.runloop.certificate", function()
  describe("produce_wild_snis", function()
    it("throws an error when arg is not a string", function()
      assert.has_error(function()
        produce_wild_snis()
      end, "sni must be a string")
    end)

    it("produces suffix wildcard SNI", function()
      local prefix, suffix = produce_wild_snis("domain.test")
      assert.is_nil(prefix)
      assert.equal("domain.*", suffix)
    end)

    it("produces prefix and suffix wildcard SNIs", function()
      local prefix, suffix = produce_wild_snis("www.domain.test")
      assert.equal("*.domain.test", prefix)
      assert.equal("www.domain.*", suffix)
    end)

    it("produces prefix and suffix wildcard SNIs on sub-subnames", function()
      local prefix, suffix = produce_wild_snis("foo.www.domain.test")
      assert.equal("*.www.domain.test", prefix)
      assert.equal("foo.www.domain.*", suffix)
    end)

    it("does not produce wildcard SNIs when input is wildcard", function()
      local prefix, suffix = produce_wild_snis("*.domain.test")
      assert.equal("*.domain.test", prefix)
      assert.is_nil(suffix)

      prefix, suffix = produce_wild_snis("domain.*")
      assert.is_nil(prefix)
      assert.equal("domain.*", suffix)
    end)
  end)
  describe("cache", function()
    local get_ca_certificate_store
    local old_k

    lazy_setup(function()
      old_k = _G.kong
      _G.kong = {
        core_cache = {
          get = function() end
        }
      }

      -- reload module
      package.loaded["kong.runloop.certificate"] = nil
      certificate = require "kong.runloop.certificate"

      get_ca_certificate_store = certificate.get_ca_certificate_store
    end)

    lazy_teardown(function()
      _G.kong = old_k
    end)

    it("uses sha256_hex for the ca_id cache key", function()
      local ca_id = uuid()
      local spy_cache = spy.on(kong.core_cache, "get")

      get_ca_certificate_store({ ca_id })

      local expected_key = "ca_stores:" .. sha256_hex(ca_id)
      assert.spy(spy_cache).was.called_with(
        match.is_table(),
        expected_key,
        match.is_table(),
        match.is_function(),
        match.is_table()
      )
    end)
  end)
end)
