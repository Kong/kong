local utils = require "kong.tools.utils"

describe("keyring", function()
  local keyring = require "kong.keyring"
  local MOCK_ID = "mock_id"
  local MOCK_VALUE = utils.get_rand_bytes(32)

  describe("backoff", function()
    setup(function()
      _G.kong = {
        configuration = {
          db_update_frequency = 5,
          keyring_enabled = true,
        }
      }

      ngx.shared.kong_keyring:set(MOCK_ID, MOCK_VALUE)
      ngx.shared.kong_keyring:set("active", MOCK_ID)
    end)

    local r = function() return true end
    local s = function(m) return true end
    local t = function(m) return false, m end

    describe("executes a function successfully", function()
      it("with no params", function()
        assert(keyring.backoff(r))
      end)

      it("with one param", function()
        assert(keyring.backoff(s, "foo"))
      end)
    end)

    describe("times out when a function", function()
      it("returns false", function()
        local res, err = keyring.backoff(t, { max = 1, max_iter = 1 })
        assert.is_nil(res)
        assert.same("timeout", err)
      end)

      it("returns false and an error", function()
        local res, err = keyring.backoff(t, { max = 1, max_iter = 1 }, "err msg")
        assert.is_nil(res)
        assert.same("err msg", err)
      end)
    end)
  end)

  describe("encrypt", function()
    it("returns a string as an encrypted blob", function()
      local res = keyring.encrypt("supersecretgogogadget")
      assert.matches("%$ke%$1%$%-mock_id%-[%x]+%-[%x]+$", res)
    end)

    it("does not encrypt an already-encrypted value", function()
      local s = "$ke$1$" .. "imalreadyencrypted"
      assert.matches(s, keyring.encrypt(s))
    end)

    it("returns when no plaintext is provided", function()
      assert.is_nil(keyring.encrypt(nil))
    end)

    it("errors when passed a non-string", function()
      assert.has_errors(function() keyring.encrypt(true) end)
    end)

    describe("errors when failing to fetch the active key", function()
      local ref
      setup(function()
        ref = keyring.active_key
        keyring.active_key = function() error("nope") end
      end)

      teardown(function()
        keyring.active_key = ref
      end)

      it("", function()
        assert.has_error(function() keyring.encrypt("abeautifulerror") end, "nope")
      end)
    end)

    describe("errors when using an invalid key", function()
      local ref
      setup(function()
        ref = keyring.active_key
        keyring.active_key = function() return "nope", nil, "nope" end
      end)

      teardown(function()
        keyring.active_key = ref
      end)

      it("", function()
        assert.has_error(function() keyring.encrypt("abeautifulerror") end,
                         "bad argument #1 to 'encrypt' (4: invalid key length (should be 32))")
      end)
    end)
  end)

  describe("decrypt", function()
    local ciphertext
    local MOCK_STRING = "this is the song that never ends"

    setup(function()
      ciphertext = keyring.encrypt(MOCK_STRING)
    end)

    it("decrypts a string", function()
      local res = keyring.decrypt(ciphertext)
      assert.same(res, MOCK_STRING)
    end)

    it("returns the same string that doesn't hold the marker", function()
      local s = "im not encrypted"
      assert.same(s, keyring.decrypt(s))
    end)

    it("errors with a malformed encrypted blob", function()
      -- this blob doesnt have a separator (:) between an IV and ciphertext
      local s = "$ke$1$:" .. MOCK_ID .. ":c080cc6e73de4da3874fbfb333f961f8"
      assert.has_error(function() keyring.decrypt(s) end)
    end)
  end)

  describe("keyring_add", function()
    local NEW_MOCK_ID = "foo"

    teardown(function()
      ngx.shared.kong_keyring:delete(NEW_MOCK_ID)
    end)

    describe("returns true", function()
      it("adding a key to the keyring", function()
        local ok = keyring.keyring_add(NEW_MOCK_ID, "bar")
        assert.is_true(ok)
      end)
    end)

    describe("returns false", function()
      local ref

      setup(function()
        ref = ngx.shared.kong_keyring.set
        ngx.shared.kong_keyring.set = function() return false, "nope" end
      end)

      teardown(function()
        ngx.shared.kong_keyring.set = ref
      end)

      it("failing to write to the shared dictionary", function()
        local ok, err = keyring.keyring_add("foo", "bar")
        assert.is_false(ok)
        assert.same(err, "nope")
      end)
    end)
  end)

  describe("keyring_remove", function()
    local NEW_MOCK_ID = "foo"

    teardown(function()
      ngx.shared.kong_keyring:delete(NEW_MOCK_ID)
    end)

    describe("returns true", function()
      setup(function()
        keyring.keyring_add(NEW_MOCK_ID, "bar")
      end)

      it("removing a key from the keyring", function()
        local ok = keyring.keyring_remove(NEW_MOCK_ID)
        assert.is_true(ok)
      end)
    end)

    describe("returns false", function()
      it("attempting to remove the active key", function()
        local ok, err = keyring.keyring_remove(MOCK_ID)
        assert.is_false(ok)
        assert.is_same(err, "cannot remove active key")
      end)
    end)
  end)

  describe("get_key_ids", function()
    describe("returns the key ids", function()
      it("in the keyring", function()
        assert.same({ MOCK_ID }, keyring.get_key_ids())
      end)

      describe("after adding a new key", function()
        local NEW_MOCK_ID = "foo"

        setup(function()
          keyring.keyring_add(NEW_MOCK_ID, "foo")
        end)

        teardown(function()
          ngx.shared.kong_keyring:delete(NEW_MOCK_ID)
        end)

        it("", function()
          local key_ids = keyring.get_key_ids()
          table.sort(key_ids)

          local mock_key_ids = { NEW_MOCK_ID, MOCK_ID }
          table.sort(mock_key_ids)
          assert.same(mock_key_ids, key_ids)
        end)
      end)
    end)
  end)

  describe("get_keys", function()
    it("returns a table of keys with encoded values", function()
      local t = keyring.get_keys()
      assert.is_table(t)
      assert.same(t[MOCK_ID], ngx.encode_base64(MOCK_VALUE))
    end)

    it("returns a table of key with raw values", function()
      local t = keyring.get_keys(true)
      assert.is_table(t)
      assert.same(t[MOCK_ID], MOCK_VALUE)
    end)

    it("returns a table that does not include the 'active' key", function()
      local t = keyring.get_keys()
      assert.is_nil(t["active"])
    end)
  end)

  describe("get_key", function()
    it("returns a key value", function()
      assert.same(MOCK_VALUE, keyring.get_key(MOCK_ID))
    end)

    describe("errors", function()
      it("failing to find the given key", function()
        local k, err = keyring.get_key("foo")
        assert.is_nil(k)
        assert.is_same(err, "key not found")
      end)

      describe("when ngx.DICT fails", function()
        local ref
        local MOCK_ERR = "mock err"

        setup(function()
          ref = ngx.shared.kong_keyring.get
          ngx.shared.kong_keyring.get = function() return nil, MOCK_ERR end
        end)

        teardown(function()
          ngx.shared.kong_keyring.get = ref
        end)

        it("", function()
          local k, err = keyring.get_key(MOCK_ID)
          assert.is_nil(k)
          assert.is_same(err, MOCK_ERR)
        end)
      end)
    end)
  end)

  describe("active_key", function()
    describe("returns the active key and id", function()
      it("", function()
        local key, err, id = keyring.active_key()
        assert.same(MOCK_VALUE, key)
        assert.is_nil(err)
        assert.same(MOCK_ID, id)
      end)
    end)

    describe("errors", function()
      describe("failing to fetch the active key id", function()
        setup(function()
          ngx.shared.kong_keyring:delete("active")
        end)

        teardown(function()
          ngx.shared.kong_keyring:set("active", MOCK_ID)
        end)

        it("", function()
          local key, err = keyring.active_key()
          assert.is_nil(key)
          assert.same(err, "active key id not found")
        end)
      end)

      describe("faiing to fetch the active key", function()
        setup(function()
          ngx.shared.kong_keyring:delete(MOCK_ID)
        end)

        teardown(function()
          ngx.shared.kong_keyring:set(MOCK_ID, MOCK_VALUE)
        end)

        it("", function()
          local key, err = keyring.active_key()
          assert.is_nil(key)
          assert.same(err, "active key not found")
        end)
      end)
    end)
  end)

  describe("activate_local", function()
    describe("activates a new key", function()
      local ref
      local NEW_MOCK_ID = "new_mock_id"

      local MOCK_BUF = {}

      setup(function()
        keyring.keyring_add(NEW_MOCK_ID)
        ref = ngx.log
        ngx.log = function(lvl, ...) -- luacheck: ignore
          local t = table.pack(...)
          table.insert(MOCK_BUF, table.concat(t, ""))
        end
      end)

      teardown(function()
        ngx.shared.kong_keyring:delete(NEW_MOCK_ID)
        ngx.shared.kong_keyring:set("active", MOCK_ID)
        ngx.log = ref -- luacheck: ignore
      end)

      it("", function()
        local ok, err = keyring.activate_local(NEW_MOCK_ID)
        assert.is_true(ok)
        assert.is_nil(err)
        assert.same(MOCK_BUF[1], "[keyring] activating key '" .. NEW_MOCK_ID .. "'")
      end)
    end)

    describe("errors", function()
      describe("when the key is not found", function()
        it("", function()
          local ok, err = keyring.activate_local("DNE")
          assert.is_false(ok)
          assert.same(err, "not found")
        end)
      end)

      describe("when the fetching the active key id fails", function()
        local ref
        local MOCK_ERR = "mock err"

        setup(function()
          ref = ngx.shared.kong_keyring.set
          ngx.shared.kong_keyring.set = function() return false, MOCK_ERR end
        end)

        teardown(function()
          ngx.shared.kong_keyring.set = ref
        end)

        it("", function()
          local ok, err = keyring.activate_local(MOCK_ID)
          assert.is_false(ok)
          assert.is_same(err, MOCK_ERR)
        end)
      end)
    end)
  end)

  describe("new_id", function()
    it("returns a new id", function()
      assert.matches("^" .. string.rep("%w", 8) .. "$", keyring.new_id())
    end)
  end)
end)
