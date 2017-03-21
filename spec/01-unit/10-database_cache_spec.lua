local cache = require "kong.tools.database_cache"
local json = require "cjson"

describe("Database cache", function()

  it("returns a valid API cache key", function()
    assert.are.equal("apis:httpbin.org", cache.api_key("httpbin.org"))
  end)

  it("returns a valid PLUGIN cache key", function()
    assert.are.equal("plugins:authentication:api123:app123", cache.plugin_key("authentication", "api123", "app123"))
    assert.are.equal("plugins:authentication:api123", cache.plugin_key("authentication", "api123"))
  end)

  it("returns a valid KeyAuthCredential cache key", function()
    assert.are.equal("keyauth_credentials:username", cache.keyauth_credential_key("username"))
  end)

  it("returns a valid BasicAuthCredential cache key", function()
    assert.are.equal("basicauth_credentials:username", cache.basicauth_credential_key("username"))
  end)

  it("returns a valid HmacAuthCredential cache key", function()
    assert.are.equal("hmacauth_credentials:username", cache.hmacauth_credential_key("username"))
  end)

  it("returns a valid JWTAuthCredential cache key", function()
    assert.are.equal("jwtauth_credentials:hello", cache.jwtauth_credential_key("hello"))
  end)

  it("returns a valid LDAPAuthcredentials cache key", function()
    assert.are.equal("ldap_credentials_0c704b70-3f30-49ad-9418-3968e53c8d98:username", cache.ldap_credential_key("0c704b70-3f30-49ad-9418-3968e53c8d98", "username"))
  end)

  describe("multi-level cache", function()
    
    local key = "my_cache_key"
    local val = { sentinel = {} }

    after_each(function()
      cache.delete_all()
    end)
  
    it("stores scalar entries in the 1st and 2nd level cache", function()
      -- make sure the caches are empty
      assert.is.Nil(cache.get(key))
      assert.is.Nil(cache.sh_get(key))
      -- set a value
      assert(cache.set(key, val, nil))
      -- verify it was set
      assert.are.equal(val, cache.get(key)) -- table based unique equality
      assert.are.same(val, json.decode((cache.sh_get(key)))) -- similarity only
    end)

    it("stores scalar entries in the 1st and 2nd level cache", function()
      val = 15
      -- make sure the caches are empty
      assert.is.Nil(cache.get(key))
      assert.is.Nil(cache.sh_get(key))
      -- set a value
      assert(cache.set(key, val, nil))
      -- verify it was set
      assert.are.equal(val, cache.get(key))
      assert.are.equal(val, json.decode((cache.sh_get(key))))
    end)

    it("stores 2nd level entries in the 1st level cache", function()
      -- make sure the caches are empty
      assert.is.Nil(cache.get(key))
      assert.is.Nil(cache.sh_get(key))
      -- set a value in 2nd level
      assert(cache.sh_set(key, json.encode(val)))
      -- verify it was set
      local entry = cache.get(key)  -- should populate 1st level
      assert.are.same(val, entry) -- deserialized, so similarity only
      -- now if we get it again, it comes from 1st level, and hence 
      -- should have unique equality
      assert.are.equal(entry, cache.get(key))
    end)
  
    it("expires properly on given ttl", function()
      -- make sure the caches are empty
      assert.is.Nil(cache.get(key))
      assert.is.Nil(cache.sh_get(key))
      -- set a value, and wait for expiring
      assert(cache.set(key, val, 0.1))
      cache.sh_delete(key) -- delete from 2nd level, as these tests are using a fake lua-version-shm anyway
      assert(cache.get(key))
      ngx.sleep(0.2)
      -- verify
      assert.is.Nil(cache.get(key))
    end)
    
    it("expires properly on ttl in 1st level, provided by 2nd level", function()
      -- make sure the caches are empty
      assert.is.Nil(cache.get(key))
      assert.is.Nil(cache.sh_get(key))
      -- set a value, with a ttl in 2nd level
      cache.sh_set(key, json.encode({
              value = val,
              ___expire_ttl = ngx.now() + 0.1,
            }), 0.1)
      assert(cache.get(key)) -- should populate 1st level, including ttl setting
      cache.sh_delete(key) -- delete from 2nd level, as these tests are using a fake lua-version-shm anyway
      -- wait for expiring
      ngx.sleep(0.2)
      -- verify
      assert.is.Nil(cache.get(key))
    end)

    it("get_or_set only returns a single value on success", function()
      local cb = function() return 1,2,3,4 end
      local a,b,c,d = cache.get_or_set("just some key", nil, cb)
      assert.equal(1, a)
      assert.is_nil(b)
      assert.is_nil(c)
      assert.is_nil(d)

      -- try again, while retrieving the cached value
      local cb = function() return "result",2,3,4 end
      local a,b,c,d = cache.get_or_set("just some key", nil, cb)
      assert.equal(1, a)  -- still 1, cached value
      assert.is_nil(b)
      assert.is_nil(c)
      assert.is_nil(d)
    end)

    it("get_or_set returns all values on failure", function()
      local cb = function() return nil,2,3,4 end
      local a,b,c,d = cache.get_or_set("just some other key", nil, cb)
      assert.is_nil(a)
      assert.equal(2, b)
      assert.equal(3, c)
      assert.equal(4, d)
    end)

  end)
end)
