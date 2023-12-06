-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local helpers = require("spec.helpers")
local utils = require("kong.tools.utils")
local cjson_decode = require("cjson").decode
local cjson_encode = require("cjson").encode


local test_config =
{
  version = "1.0",
  services = {
    {
      name = "mockbin",
      url = "http://mockbin.test",
      routes = {
        {
          name = "mockbin-r1",
          paths = { "/test1", },
        }
      }
    }
  }
}


local test_config_encoded = cjson_encode(test_config)
local current_config, current_hash
local uploaded_config


-- This table can be indexed by any keys of any depth,
-- and returns the same table if you call it.
-- This is useful when unit testing a module that refers kong
--
-- You can do this:
-- _G.kong = helpers.never_error_table
-- or if you want to mock some functions:
-- _G.kong = { ... mocking codes }
-- setmetatable(_G.kong, helpers.never_error_table)
--
-- So typical reference to kong won't cause errors:
-- kong.log(...)
-- kong.db.some_model:find(...)
-- assert(kong.get_something()):call_something(...)
-- ok, err = kong.some_module.some_function(...); if err then ... end
local never_error_table
never_error_table = {
  __index = function()
    return never_error_table
  end,
  __call = function ()
    return never_error_table
  end
}
setmetatable(never_error_table, never_error_table)


local function mocking()
  -- mocking s3 support
  local mock_s3 = {}
  local mock_s3_mt = { __index = mock_s3, }

  function mock_s3.new()
    return setmetatable({}, mock_s3_mt)
  end

  function mock_s3:backup_config(cfg)
    uploaded_config = cfg
    return true
  end

  function mock_s3:fetch_config()
    return uploaded_config
  end

  function mock_s3:init_worker()
    -- do nothing
  end

  -- mocking declarative
  local mock_declarative = {}
  local mock_declarative_mt = { __index = mock_declarative, }

  function mock_declarative.new()
    return setmetatable(mock_declarative, mock_declarative_mt)
  end

  function mock_declarative:export_config()
    return current_config
  end

  function mock_declarative:new_config()
    return {
      parse_table = function(self, cfg, hash)
        current_config = cfg
        current_hash = hash or "aa9dc1b842a653dea846903ddb95bfb8c5a10c504a7fa16e10bc31d1fdf0"
        return true
      end
    }
  end

  function mock_declarative:get_current_hash()
    return current_hash
  end

  function mock_declarative:load_into_cache_with_events()
    -- do nothing
  end

  package.loaded["kong.clustering.config_sync_backup.strategies.s3"] = mock_s3
  package.loaded["kong.db.declarative"] = mock_declarative

  local registed_events = {}

  _G.kong = {
    worker_events = {
      register = function(func, source, event)
        registed_events[source] = registed_events[source] or {}
        registed_events[source][event] = func
      end,
      post = function(source, event, ...)
        if not (registed_events[source] and registed_events[source][event]) then
          return
        end
        registed_events[source][event](...)
      end,
    },

    db = {
      declarative_config = mock_declarative:new_config(),
    },
  }
  setmetatable(_G.kong, never_error_table)
end


local cluster_fallback_config_storage = "s3://test_bucket/test_prefix"


local get_phase = ngx.get_phase

local function init_phase() return "init" end


describe("cp outage handling driver", function()
  local config_sync_backup

  lazy_setup(function()
    -- initialization
    mocking()
  end)


  before_each(function()
    current_config, current_hash, uploaded_config = nil, nil, nil
  end)


  pending("upload (we cannot stop the timer)", function()
    local fake_conf = {
      role = "data_plane",
      cluster_fallback_config_storage = cluster_fallback_config_storage,
      cluster_fallback_config_export = true,
    }

    ngx.get_phase = init_phase -- luacheck: ignore
    config_sync_backup = require "kong.clustering.config_sync_backup"
    config_sync_backup.init(fake_conf)
    ngx.get_phase = get_phase -- luacheck: ignore

    config_sync_backup.init_worker(fake_conf, "exporter")
    current_config = utils.cycle_aware_deep_copy(test_config)
    kong.worker_events.post("declarative", "reconfigure", { wrpc = true })
    helpers.pwait_until(function()
      assert.same(test_config, cjson_decode(uploaded_config))
    end, 10)
  end)


  it("download", function()
    local fake_conf = {
      role = "data_plane",
      cluster_fallback_config_storage = cluster_fallback_config_storage,
      cluster_fallback_config_import = true,
    }

    ngx.get_phase = init_phase -- luacheck: ignore
    config_sync_backup = require "kong.clustering.config_sync_backup"
    config_sync_backup.init(fake_conf)
    ngx.get_phase = get_phase -- luacheck: ignore

    config_sync_backup.init_worker(fake_conf, "importer")
    uploaded_config = test_config_encoded

    config_sync_backup.import(fake_conf)
    helpers.pwait_until(function()
      assert.same(cjson_decode(uploaded_config), current_config)
    end, 10)
  end)
end)

-- todo: gcp
