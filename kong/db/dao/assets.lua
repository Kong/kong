local utils = require "kong.tools.utils"
local build_plugins_iterator = require("kong.runloop.handler").build_plugins_iterator
local clear_loaded_plugins = require("kong.runloop.plugins_iterator").clear_loaded
local cjson = require "cjson"

local Assets = {}

local assets_prefix = (kong.configuration.prefix or require("pl.path").abspath(ngx.config.prefix())) .. "/streamed_assets/"
package.path = package.path .. ";" .. assets_prefix .. "/?.lua;" .. assets_prefix .. "/?/init.lua;"


function Assets:load(asset_id_or_name, plugin_name)
  local asset, err
  if asset_id_or_name.id then
    asset, err = self.db.assets:select(asset_id_or_name)
  elseif asset_id_or_name.name then
    ngx.log(ngx.ERR, "n mae")
    asset, err = self.db.assets:select_by_name(asset_id_or_name.name)
  else
    return false, nil -- fall through
  end

  ngx.log(ngx.ERR, "---- asset:load ", require("inspect")(asset), " err: ", err)

  if not asset then
    return false, nil -- fall through
  end

  ngx.log(ngx.ERR, "> request to reload now ", plugin_name)

  -- os.execute("mkdir -p " .. assets_prefix)
  -- local streamed_plugins_conf = io.open(assets_prefix .. "/streamed_plugins.conf")
  -- local streamed_plugins = {}
  -- if streamed_plugins_conf then
  --   streamed_plugins = cjson.decode(streamed_plugins_conf:read("*a"))
  --   streamed_plugins[plugin_name] = true
  --   streamed_plugins_conf:close()
  -- end
  -- streamed_plugins_conf = io.open(assets_prefix .. "/streamed_plugins.conf", "w")
  -- streamed_plugins_conf:write(cjson.encode(streamed_plugins))
  -- streamed_plugins_conf:close()

  local pkg_prefix = "kong.plugins." .. plugin_name .. "."
  for k, _ in pairs(package.loaded) do
    if k:sub(1, #pkg_prefix) == pkg_prefix then
      package.loaded[k] = nil
    end
  end

  kong.configuration.loaded_plugins[plugin_name] = true
  local ok, err = kong.db.plugins:load_plugin_schemas(kong.configuration.loaded_plugins)
  if not ok then
    return false, err
  end

  clear_loaded_plugins()
  local ok, err = build_plugins_iterator("newnew")
  if err then
    return false, "failed to update plugins iterator: " .. err
  end

  return asset
end

function Assets:select(primary_key, options)
  local thing, err, err_t = self.super.select(self, primary_key, options)
  if not thing and kong.configuration.role == "data_plane" then
    ngx.log(ngx.ERR, " -> DP request asset ", require("inspect")(primary_key))
    thing, err = kong.rpc:call("control_plane", "kong.plugin_streaming.v1.request_asset_content", primary_key.id)
    if not err then
      return thing
    end
    ngx.log(ngx.ERR, "the error is ", require("inspect")(err))
  end

  return thing, err, err_t
end

function Assets:truncate()
  return self.super.truncate(self)
end

function Assets:page(size, offset, options)
  return self.super.page(self, size, offset, options)
end

function Assets:each(size, options)
  return self.super.each(self, size, options)
end

function Assets:insert(entity, options)
  return self.super.insert(self, entity, options)
end

function Assets:update(primary_key, entity, options)
  return self.super.update(self, primary_key, entity, options)
end

function Assets:upsert(primary_key, entity, options)
  return self.super.upsert(self, primary_key, entity, options)
end

function Assets:delete(primary_key, options)
  return self.super.delete(self, primary_key, options)
end

function Assets:select_by_cache_key(cache_key, options)
  return self.super.select_by_cache_key(self, cache_key, options)
end

function Assets:page_for_set(foreign_key, size, offset, options)
  return self.super.page_for_set(self, foreign_key, size, offset, options)
end

function Assets:each_for_set(foreign_key, size, options)
  return self.super.each_for_set(self, foreign_key, size, options)
end


return Assets