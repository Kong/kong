local _M = {}

local cjson = require "cjson"
local pl_path = require "pl.path"
local digest = require "resty.openssl.digest"
local utils = require "kong.tools.utils"
local hasher = digest.new("sha256")
local to_hex = require("resty.string").to_hex
local build_plugins_iterator = require("kong.runloop.handler").build_plugins_iterator
local clear_loaded_plugins = require("kong.runloop.plugins_iterator").clear_loaded

local assets_prefix = (kong.configuration.prefix or require("pl.path").abspath(ngx.config.prefix())) .. "/streamed_assets/"
package.path = package.path .. ";" .. assets_prefix .. "/?.lua;" .. assets_prefix .. "/?/init.lua;"

local function from_hex(s)
  local hex_to_char = {}
  for idx = 0, 255 do
  hex_to_char[("%02X"):format(idx)] = string.char(idx)
  hex_to_char[("%02x"):format(idx)] = string.char(idx)
  end

  return s:gsub("(..)", hex_to_char)
end


-- local function stream_asset_metadata(_node_id, asset_id, metadata)
--   ngx.log(ngx.ERR, "> got ", _node_id, ", ", require("inspect")(metadata))
--   metadata.tmpname = pl_path.tmpname()
--   metadata.consumed_bytes = 0
--   metadata.consumed_seq = 0
--   assert(ngx.shared.kong:set("plugin_streaming_assets::" .. asset_id, cjson.encode(metadata), 60))

--   return true
-- end


-- this RPC is invoked on DP and exeucted on CP
local function request_asset_content(_node_id, asset_uuid)
  local asset, err

  ngx.log(ngx.ERR, "asset_id is ", asset_uuid)

  local asset, err = kong.db.assets:select({ id = asset_uuid })

  if err then
    return nil, "error fetching asset: " .. err
  elseif not asset then
    return nil, "asset not found"
  end

  local metadata = asset.metadata

  local contentfp = io.open(assets_prefix .. "/" .. metadata.sha256sum .. ".assetbundle")
  if not contentfp then
    return nil, "asset file not found"
  end

  metadata.seq = 1
  while true do
    local partial = contentfp:read(2 * 1024 * 1024) -- 2M
    if not partial then
      break
    end
    local res, err = kong.rpc:call(_node_id, "kong.plugin_streaming.v1.stream_asset_content", asset_uuid, partial, metadata)
    if not res then
      return nil, "failed streaming assets " .. err
    end
    metadata.seq = metadata.seq + 1
  end

  ngx.log(ngx.ERR, "-> request_asset_content done")

  return asset, nil
end


-- this RPC is invoked on CP and exeucted on DP
local function stream_asset_content(_node_id, asset_uuid, content, metadata)
  local progress = ngx.shared.kong:get("plugin_streaming_assets::" .. asset_uuid)
  if not progress then
    progress = {
      tmpname = pl_path.tmpname(),
      consumed_bytes = 0,
      consumed_seq = 0,
    }
  else
    progress = cjson.decode(progress)
  end

  ngx.log(ngx.ERR, " metadata ", require("inspect")(metadata), " progress ", require("inspect")(progress))

  if metadata.seq <= progress.consumed_seq then
    return false, "out of order data received"
  end

  local f = io.open(progress.tmpname, "a")
  assert(f:write(content))
  assert(f:close())

  progress.consumed_bytes = progress.consumed_bytes + #content
  progress.consumed_seq = metadata.seq

  if progress.consumed_bytes == metadata.size then
    ngx.log(ngx.ERR, ">> file download complete")
    ngx.shared.kong:delete("plugin_streaming_assets::" .. asset_uuid)
    assert(hasher:reset())
    local got, err = hasher:final(io.open(progress.tmpname):read("*a"))
    if err then
      return false, "failed to hash file: " .. err
    end

    if got ~= from_hex(metadata.sha256sum) then
      return false, "checksum mismatch: got " .. to_hex(got) .. ", expected " .. metadata.sha256sum
    end
    ngx.log(ngx.ERR, ">> file verifies")
    os.execute("mkdir -p " .. assets_prefix .. " ; tar zxvf " .. progress.tmpname .. " -C " .. assets_prefix)
    ngx.log(ngx.ERR, ">> file extracts")
  else
    ngx.log(ngx.ERR, ">> file download ", progress.consumed_bytes, " / ", metadata.size)
  end

  assert(ngx.shared.kong:set("plugin_streaming_assets::" .. asset_uuid, cjson.encode(progress), 60))

  return true
end

local function reload_plugins(_node_id, plugin_name)
  ngx.log(ngx.ERR, "> request to reload now ", plugin_name)

  local pkg_prefix = "kong.plugins." .. plugin_name .. "."
  for k, v in pairs(package.loaded) do
    if k:sub(1, #pkg_prefix) == pkg_prefix then
      package.loaded[k] = nil
    end
  end

  kong.configuration.loaded_plugins[plugin_name] = true
  assert(kong.db.plugins:load_plugin_schemas(kong.configuration.loaded_plugins))

  clear_loaded_plugins()
  local ok, err = build_plugins_iterator("newnew")
  if err then
    return false, "failed to update plugins iterator: " .. err
  end

  return true
end

_M.reload_plugins = reload_plugins


function _M.init(manager)
  manager.callbacks:register("kong.plugin_streaming.v1.request_asset_content", request_asset_content)
  manager.callbacks:register("kong.plugin_streaming.v1.stream_asset_content", stream_asset_content)
  manager.callbacks:register("kong.plugin_streaming.v1.reload_plugins", reload_plugins)
end


return _M
