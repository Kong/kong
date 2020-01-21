local storage = require("kong.plugins.acme.storage.kong")

local helpers = require "spec.helpers"


for _, strategy in helpers.each_strategy() do
  describe("Plugin: acme (storage.kong) [#" .. strategy .. "]", function()
    local _, db

    lazy_setup(function()
      _, db = helpers.get_db_utils(strategy, {
        "certificates",
        "snis",
        "cluster_events",
        "acme_storage",
      }, { "acme", })

      db.acme_storage:truncate()
    end)

    describe("new", function()
      it("returns no error", function()
        local a = storage.new()
        assert.not_nil(a)
      end)
    end)

    describe("set", function()
      ngx.update_time()
      local key = tostring(ngx.now()) .. "set"
      it("returns no error", function()
        local a = storage.new()
        local err = a:set(key, "set")
        assert.is_nil(err)

        err = a:set(key, "set2")
        assert.is_nil(err)
      end)
    end)

    describe("get", function()
      ngx.update_time()
      local key = tostring(ngx.now()) .. "get"
      it("returns no error", function()
        local a = storage.new()
        local v, err

        err = a:set(key, "get")
        assert.is_nil(err)

        v, err = a:get(key)
        assert.is_nil(err)
        assert.same("get", v)

        err = a:set(key, "get2")
        assert.is_nil(err)

        v, err = a:get(key)
        assert.is_nil(err)
        assert.same("get2", v)
      end)
    end)

    describe("delete", function()
      ngx.update_time()
      local key = tostring(ngx.now()) .. "delete"
      it("returns no error", function()
        local a = storage.new()
        local v, err
        err = a:set(key, "delete")
        assert.not_nil(a)
        assert.is_nil(err)

        v, err = a:get(key)
        assert.is_nil(err)
        assert.same("delete", v)

        err = a:delete(key)
        assert.is_nil(err)
        assert.same("delete", v)

        v, err = a:get(key)
        assert.is_nil(err)
        assert.is_nil(v)
      end)
    end)

    describe("set with ttl", function()
      ngx.update_time()
      local key = tostring(ngx.now()) .. "setttl"
      local a = storage.new()
      local err, v
      it("returns no error", function()

        err = a:set(key, "setttl", 2)
        assert.is_nil(err)

        v, err = a:get(key)
        assert.is_nil(err)
        assert.same("setttl", v)
      end)

      it("cleans up expired key", function()
        ngx.sleep(2)

        v, err = a:get(key)
        assert.is_nil(err)
        assert.is_nil(v)
      end)
    end)

    describe("add without ttl", function()
      ngx.update_time()
      local key = tostring(ngx.now()) .. "add"
      local a = storage.new()
      local err, v
      it("returns no error", function()
        err = a:add(key, "add")
        assert.is_nil(err)

        v, err = a:get(key)
        assert.is_nil(err)
        assert.same("add", v)
      end)
      it("errors when key exists", function()
        err = a:add(key, "add2")
        assert.same("exists", err)

        v, err = a:get(key)
        assert.is_nil(err)
        assert.same("add", v)
      end)
    end)

    describe("add with ttl", function()
      ngx.update_time()
      local key = tostring(ngx.now()) .. "addttl"
      local a = storage.new()
      local err, v
      it("returns no error", function()

        err = a:add(key, "addttl", 2)
        assert.is_nil(err)

        v, err = a:get(key)
        assert.is_nil(err)
        assert.same("addttl", v)
      end)

      it("cleans up expired key", function()
        ngx.sleep(2)

        v, err = a:get(key)
        assert.is_nil(err)
        assert.is_nil(v)
      end)
    end)

    describe("list", function()
      ngx.update_time()
      local prefix = tostring(ngx.now()) .. "list_"
      local a = storage.new()
      local err, keys
      for i=1,10,1 do
        err = a:set(prefix .. tostring(i), " ")
        assert.is_nil(err)
      end

      it("returns all keys with no parameter", function()
        keys, err = a:list()
        assert.is_nil(err)
        assert.not_nil(keys)
        table.sort(keys)

        local rows = db.acme_storage:page(100)
        local expected_keys = {}
        for i, row in ipairs(rows) do
          expected_keys[i] = row.key
        end
        table.sort(expected_keys)

        assert.same(expected_keys, keys)

      end)

      it("returns keys with given prefix", function()
        keys, err = a:list(prefix)
        assert.is_nil(err)
        assert.not_nil(keys)

        assert.same(10, #keys)
      end)

      it("returns empty table if no match", function()
        keys, err = a:list(prefix .. "_")
        assert.is_nil(err)
        assert.not_nil(keys)

        assert.same(0, #keys)
      end)
    end)
  end)
end
