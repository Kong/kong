-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local helpers
local buffer
local kong_global
local conf_loader
local declarative
local DB

local kong


local ngx_log = ngx.log
local ngx_debug = ngx.DEBUG
local lmdb_mlcache
do
  local resty_mlcache = require "kong.resty.mlcache"
  lmdb_mlcache = assert(resty_mlcache.new("lmdb_mlcache", "lmdb_mlcache", {
    lru_size = 1000,
    ttl      = 0,
    neg_ttl  = 0,
    resurrect_ttl = 30,
    ipc      = {
      register_listeners = function(events)
        ngx_log(ngx_debug, "register lmdb worker events ", tostring(events))
      end,
      broadcast = function(channel, data)
        ngx_log(ngx_debug, "broadcast lmdb worker events ", tostring(channel), tostring(data))
      end
    },
  }))
  lmdb_mlcache:purge(true)

  _G.lmdb_mlcache = lmdb_mlcache
end

local function mocking_lmdb_transaction()
  local _lmdb_txn = {}
  local _lmdb_txn_mt = { __index = _lmdb_txn }
  function _lmdb_txn.begin(x)
    ngx_log(ngx_debug, "new lmdb: ", x)
    local self = {
      cache = lmdb_mlcache,
      DEFAULT_DB = "_default",
    }
    return setmetatable(self, _lmdb_txn_mt)
  end

  function _lmdb_txn:db_drop(delete, db)
    ngx_log(ngx_debug, "drop db = ", db or self.DEFAULT_DB, ", delete = ", delete)
    return true
  end

  function _lmdb_txn:set(key, value, db)
    ngx_log(ngx_debug, "set db = ", db or self.DEFAULT_DB, ", ", key, " = ", value)
    self.cache:set(key, nil, value)
    return true
  end

  function _lmdb_txn:get(key, db)
    ngx_log(ngx_debug, "get db = ", db or self.DEFAULT_DB, ", key = ", key)
    return self.cache:get(key)
  end

  function _lmdb_txn:commit()
    ngx_log(ngx_debug, "commit lmdb transactions")
    return true
  end

  _G.package.loaded["resty.lmdb.transaction"] = _lmdb_txn
end

local function mocking_lmdb()
  local _lmdb = {
    cache = lmdb_mlcache,
    DEFAULT_DB = "_default"
  }
  local _lmdb_mt = { __index = _lmdb, }

  function _lmdb.get(key, db)
    ngx_log(ngx_debug, "get db = ", db or _lmdb.DEFAULT_DB, ", key = ", key)
    return _lmdb.cache:get(key)
  end

  setmetatable(_lmdb, _lmdb_mt)

  _G.package.loaded["resty.lmdb"] = _lmdb
end

local function unmocking()
  _G.package.loaded["resty.lmdb.transaction"] = nil
  _G["resty.lmdb.transaction"] = nil

  _G.package.loaded["resty.lmdb"] = nil
  _G["resty.lmdb"] = nil
end

describe("#off preserve nulls", function()
  local PLUGIN_NAME = "preserve-nulls"
  local PASSWORD = "fti-110"
  local YAML_CONTENTS = string.format([=[
    _format_version: '3.0'
    services:
    - name: fti-110
      url: http://localhost/ip
      routes:
      - name: fti-110
        paths:
        - /fti-110
        plugins:
        - name: basic-auth
          config:
            hide_credentials: false
        - name: preserve-nulls
          config:
            request_header: "Hello-Foo"
            response_header: "Bye-Bar"
            large: ~
            ttl: null
    consumers:
    - username: fti-110
      custom_id: fti-110-cid
      basicauth_credentials:
      - username: fti-110
        password: %s
      keyauth_credentials:
      - key: fti-5260
  ]=], PASSWORD)

  lazy_setup(function()
    mocking_lmdb_transaction()
    require "resty.lmdb.transaction"
    mocking_lmdb()
    require "resty.lmdb"

    helpers = require "spec.helpers"
    kong = _G.kong
    kong.core_cache = nil

    buffer      = require "string.buffer"
    kong_global = require "kong.global"
    conf_loader = require "kong.conf_loader"
    declarative = require "kong.db.declarative"
    DB = require "kong.db"
  end)

  lazy_teardown(function()
    unmocking()
  end)

  it("when loading into LMDB", function()
    local null = ngx.null
    local concat = table.concat

    local kong_config = assert(conf_loader(helpers.test_conf_path, {
      database = "off",
      plugins = "bundled," .. PLUGIN_NAME,
    }))

    local db = assert(DB.new(kong_config))
    assert(db:init_connector())
    db.plugins:load_plugin_schemas(kong_config.loaded_plugins)
    db.vaults:load_vault_schemas(kong_config.loaded_vaults)
    kong.db = db

    local dc = assert(declarative.new_config(kong_config))
    local dc_table, _, _, current_hash = assert(dc:unserialize(YAML_CONTENTS, "yaml"))
    assert.are_equal(PASSWORD, dc_table.consumers[1].basicauth_credentials[1].password)

    local entities, _, _, meta, new_hash = assert(dc:parse_table(dc_table, current_hash))
    assert.is_not_falsy(meta._transform)
    assert.are_equal(current_hash, new_hash)

    for _,v in pairs(entities.plugins) do
      if v.name == PLUGIN_NAME then
        assert.are_equal(v.config.large, null)
        assert.are_equal(v.config.ttl, null)
        break
      end
    end

    kong.configuration = kong_config
    kong.worker_events = kong.worker_events or
                         kong.cache and kong.cache.worker_events or
                         assert(kong_global.init_worker_events(kong.configuration))
    kong.cluster_events = kong.cluster_events or
                          kong.cache and kong.cache.cluster_events or
                          assert(kong_global.init_cluster_events(kong.configuration, kong.db))
    kong.cache = kong.cache or
                 assert(kong_global.init_cache(kong.configuration, kong.cluster_events, kong.worker_events))
    kong.core_cache = assert(kong_global.init_core_cache(kong.configuration, kong.cluster_events, kong.worker_events))

    kong.cache.worker_events = kong.cache.worker_events or kong.worker_events
    kong.cache.cluster_events = kong.cache.cluster_events or kong.cluster_events

    assert(declarative.load_into_cache(entities, meta, current_hash))

    local id, item = next(entities.basicauth_credentials)
    local cache_key = concat({
      "basicauth_credentials:",
      id,
      ":::::",
      item.ws_id
    })

    local lmdb = require "resty.lmdb"
    local value, err, hit_lvl = lmdb.get(cache_key)
    assert.is_nil(err)
    assert.are_equal(hit_lvl, 1)

    local cached_item = buffer.decode(value)
    assert.are_not_same(cached_item, item)
    assert.are_equal(cached_item.id, item.id)
    assert.are_equal(cached_item.username, item.username)
    assert.are_not_equal(PASSWORD, cached_item.password)
    assert.are_not_equal(cached_item.password, item.password)

    for _, plugin in pairs(entities.plugins) do
      if plugin.name == PLUGIN_NAME then
        cache_key = concat({
          "plugins:" .. PLUGIN_NAME .. ":",
          plugin.route.id,
          "::::",
          plugin.ws_id
        })
        value, err, hit_lvl = lmdb.get(cache_key)
        assert.is_nil(err)
        assert.are_equal(hit_lvl, 1)

        cached_item = buffer.decode(value)
        assert.are_same(cached_item, plugin)
        assert.are_equal(cached_item.config.large, null)
        assert.are_equal(cached_item.config.ttl, null)

        break
      end
    end

  end)

end)
