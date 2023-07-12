local redis_storage = require("resty.acme.storage.redis")
local reserved_words = require "kong.plugins.acme.reserved_words"

local helpers = require "spec.helpers"

describe("Plugin: acme (storage.redis)", function()
  it("should successfully connect to the Redis SSL port", function()
    local config = {
      host = helpers.redis_host,
      port = helpers.redis_ssl_port,
      database = 0,
      auth = nil,
      ssl = true,
      ssl_verify = false,
      ssl_server_name = nil,
    }
    local storage, err = redis_storage.new(config)
    assert.is_nil(err)
    assert.not_nil(storage)
    local err = storage:set("foo", "bar", 10)
    assert.is_nil(err)
    local value, err = storage:get("foo")
    assert.is_nil(err)
    assert.equal("bar", value)
  end)

  describe("redis namespace", function()
    local config = {
      host = helpers.redis_host,
      port = helpers.redis_port,
      database = 0,
      namespace = "test",
    }
    local storage, err = redis_storage.new(config)
    assert.is_nil(err)
    assert.not_nil(storage)

    it("redis namespace set", function()
      local err = storage:set("key1", "1", 10)
      assert.is_nil(err)
      local err = storage:set("key1", "new value", 10)
      assert.is_nil(err)
    end)

    it("redis namespace get", function()
      local err = storage:set("key2", "2", 10)
      assert.is_nil(err)
      local value, err = storage:get("key2")
      assert.is_nil(err)
      assert.equal("2", value)
    end)

    it("redis namespace delete", function()
      local err = storage:set("key3", "3", 10)
      assert.is_nil(err)
      local value, err = storage:get("key3")
      assert.is_nil(err)
      assert.equal("3", value)
      local err = storage:delete("key3")
      assert.is_nil(err)

      -- now the key should be deleted
      local value, err = storage:get("key3")
      assert.is_nil(err)
      assert.is_nil(value)

      -- delete again with no error
      local err = storage:delete("key3")
      assert.is_nil(err)
    end)

    it("redis namespace add", function()
      local err = storage:set("key4", "4", 10)
      assert.is_nil(err)
      local err = storage:add("key4", "5", 10)
      assert.equal("exists", err)
      local value, err = storage:get("key4")
      assert.is_nil(err)
      assert.equal("4", value)

      local err = storage:add("key5", "5", 10)
      assert.is_nil(err)
      local value, err = storage:get("key5")
      assert.is_nil(err)
      assert.equal("5", value)
    end)

    it("redis namespace list", function()
      local err = storage:set("prefix1", "bb--", 10)
      assert.is_nil(err)
      local err = storage:set("pref-x2", "aa--", 10)
      assert.is_nil(err)
      local err = storage:set("prefix3", "aa--", 10)
      assert.is_nil(err)
      local keys, err = storage:list("prefix")
      assert.is_nil(err)
      assert.is_table(keys)
      assert.equal(2, #keys)
      table.sort(keys)
      assert.equal("prefix1", keys[1])
      assert.equal("prefix3", keys[2])

      local keys, err = storage:list("nonexistent")
      assert.is_nil(err)
      assert.is_table(keys)
      assert.equal(0, #keys)
    end)

    it("redis namespace isolation", function()
      local config0 = {
        host = helpers.redis_host,
        port = helpers.redis_port,
        database = 0,
      }
      local config1 = {
        host = helpers.redis_host,
        port = helpers.redis_port,
        database = 0,
        namespace = "namespace1",
      }
      local config2 = {
        host = helpers.redis_host,
        port = helpers.redis_port,
        database = 0,
        namespace = "namespace2",
      }
      local storage0, err = redis_storage.new(config0)
      assert.is_nil(err)
      assert.not_nil(storage0)
      local storage1, err = redis_storage.new(config1)
      assert.is_nil(err)
      assert.not_nil(storage1)
      local storage2, err = redis_storage.new(config2)
      assert.is_nil(err)
      assert.not_nil(storage2)
      local err = storage0:set("isolation", "0", 10)
      assert.is_nil(err)
      local value, err = storage0:get("isolation")
      assert.is_nil(err)
      assert.equal("0", value)
      local value, err = storage1:get("isolation")
      assert.is_nil(err)
      assert.is_nil(value)
      local value, err = storage2:get("isolation")
      assert.is_nil(err)
      assert.is_nil(value)

      local err = storage1:set("isolation", "1", 10)
      assert.is_nil(err)
      local value, err = storage0:get("isolation")
      assert.is_nil(err)
      assert.equal("0", value)
      local value, err = storage1:get("isolation")
      assert.is_nil(err)
      assert.equal("1", value)
      local value, err = storage2:get("isolation")
      assert.is_nil(err)
      assert.is_nil(value)

      local err = storage2:set("isolation", "2", 10)
      assert.is_nil(err)
      local value, err = storage0:get("isolation")
      assert.is_nil(err)
      assert.equal("0", value)
      local value, err = storage1:get("isolation")
      assert.is_nil(err)
      assert.equal("1", value)
      local value, err = storage2:get("isolation")
      assert.is_nil(err)
      assert.equal("2", value)
    end)

    -- irrelevant to db, just test one
    describe("validate redis namespace #postgres", function()
      local client
      local strategy = "postgres"

      lazy_setup(function()
        helpers.get_db_utils(strategy, {
          "plugins",
        }, {
          "acme"
        })

        assert(helpers.start_kong({
          database = strategy,
        }))
      end)

      lazy_teardown(function()
        helpers.stop_kong(nil, true)
      end)

      before_each(function()
        client = helpers.admin_client()
      end)

      after_each(function()
        if client then
          client:close()
        end
      end)

      it("successfully create acme plugin with valid namespace", function()
        local res = assert(client:send {
          method = "POST",
          path = "/plugins",
          headers = { ["Content-Type"] = "application/json" },
          body = {
            name = "acme",
            config = {
              account_email = "test@test.com",
              api_uri = "https://api.acme.org",
              storage = "redis",
              preferred_chain = "test",
              storage_config = {
                redis = {
                  host = helpers.redis_host,
                  port = helpers.redis_port,
                  namespace = "namespace1:",
                },
              },
            },
          },
        })
        assert.res_status(201, res)
      end)

      it("fail to create acme plugin with invalid namespace", function()
        for _, v in pairs(reserved_words) do
          local res = assert(client:send {
            method = "POST",
            path = "/plugins",
            headers = { ["Content-Type"] = "application/json" },
            body = {
              name = "acme",
              config = {
                account_email = "test@test.com",
                api_uri = "https://api.acme.org",
                storage = "redis",
                preferred_chain = "test",
                storage_config = {
                  redis = {
                    host = helpers.redis_host,
                    port = helpers.redis_port,
                    namespace = v,
                  },
                },
              },
            },
          })
          local body = assert.res_status(400, res)
          assert.matches("namespace can't be prefixed with reserved word: " .. v, body)
        end
      end)
    end)
  end)

  describe("Plugin: acme (handler.access) [#postgres]", function()
    local bp
    local domain = "mydomain.com"
    local dummy_id = "ZR02iVO6PFywzFLj6igWHd6fnK2R07C-97dkQKC7vJo"
    local namespace = "namespace1"
    local plugin

    local function prepare_redis_data()
      local redis = require "resty.redis"
      local red = redis:new()
      red:set_timeouts(3000, 3000, 3000) -- 3 sec

      assert(red:connect(helpers.redis_host, helpers.redis_port))
      assert(red:multi())
      assert(red:set(dummy_id .. "#http-01", "default"))
      assert(red:set(namespace .. dummy_id .. "#http-01", namespace))
      assert(red:exec())
      assert(red:close())
    end

    lazy_setup(function()
      bp = helpers.get_db_utils("postgres", {
        "services",
        "routes",
        "plugins",
      }, { "acme", })

      assert(bp.routes:insert {
        paths = { "/" },
      })

      plugin = assert(bp.plugins:insert {
        name = "acme",
        config = {
          account_email = "test@test.com",
          api_uri = "https://api.acme.org",
          domains = { domain },
          storage = "redis",
          storage_config = {
            redis = {
              host = helpers.redis_host,
              port = helpers.redis_port,
              -- namespace: "", default to empty
            },
          },
        },
      })

      assert(helpers.start_kong({
        plugins = "acme",
        database = "postgres",
      }))

      prepare_redis_data()

    end)

    lazy_teardown(function()
      helpers.stop_kong()
    end)

    it("serve http challenge in the default namespace", function()
      local proxy_client = helpers.proxy_client()
      local res = assert(proxy_client:send {
        method  = "GET",
        path    = "/.well-known/acme-challenge/" .. dummy_id,
        headers =  { host = domain }
      })

      assert.response(res).has.status(200)
      local body = res:read_body()
      assert.equal("default\n", body)
      proxy_client:close()
    end)

    it("serve http challenge in the specified namespace", function()
      local admin_client = helpers.admin_client()

      local res = assert(admin_client:send {
        method = "PATCH",
        path   = "/plugins/" .. plugin.id,
        body   = {
          name = "acme",
          config = {
            account_email = "test@test.com",
            api_uri = "https://api.acme.org",
            domains = { domain },
            storage = "redis",
            storage_config = {
              redis = {
                host = helpers.redis_host,
                port = helpers.redis_port,
                namespace = namespace,    -- change namespace
              },
            },
          },
        },
        headers = {
          ["Content-Type"] = "application/json",
        },
      })
      assert.res_status(200, res)
      admin_client:close()

      local proxy_client = helpers.proxy_client()
      -- wait until admin API takes effect
      helpers.wait_until(function()
        res = assert(proxy_client:send {
          method  = "GET",
          path    = "/.well-known/acme-challenge/" .. dummy_id,
          headers =  { host = domain }
        })
        assert.response(res).has.status(200)
        local body = res:read_body()
        return namespace.."\n" == body
      end, 10)

      proxy_client:close()
    end)
  end)

end)
