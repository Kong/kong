local declarative = require("kong.db.declarative")
local calculate_config_hash = require("kong.clustering.config_helper").calculate_config_hash
local kong_version = require "kong.meta".version
local cjson = require("cjson")
local utils = require("kong.tools.utils")
local calculate_hash = require("kong.clustering.config_helper").calculate_hash
local buffer = require("string.buffer")
local semaphore_new = require("ngx.semaphore").new
local config_helper = require("kong.clustering.config_helper")
local yield = utils.yield
local buffer_new = buffer.new
local ngx_log = ngx.log
local ngx_ERR = ngx.ERR

local CP_CONNECT_TIMEOUT = 5000

local _M = {}

local storage
local function export_config()
    if not storage then
        return
    end

    local config_table = declarative.export_config()
    yield()
    local config_hash = calculate_config_hash(config_table)

    local encoded, err = cjson.encode(config_table)
    if not encoded then
        ngx_log(ngx_ERR, "failed to encode config: ", err)
        return
    end
    yield()

    storage:backup_config(encoded, config_hash)
end

local function fetch_config(conf)
    if not storage then
        return
    end

    local encoded, hash = storage:fetch_config()
    if not encoded then
        error(hash)
        return
    end

    local config_table, err = cjson.decode(encoded)
    if not encoded then
        error(err)
        return
    end
    yield()

    assert(config_helper.update(declarative.new(conf), config_table, hash))
end

local function calculate_hashes(plugins_list)
    local buf = buffer_new()
    -- the plugin list is sorted, therefore the hash is deterministic
    return calculate_hash(plugins_list, buf)
end

local function uploader()
    local range, event
    if kong.clustering.role == "control_plane" then
        range, event = "clustering", "push_config"

    elseif kong.clustering.role == "data_plane" then
        range, event = "declarative", "reconfigure"

    else
        ngx_log(ngx_ERR, "only clustering role 'control_plane' and 'data_plane' can backup configs")
        return
    end

    kong.worker_events.register(export_config, range, event)
end

local function downloader(conf)
    if kong.clustering.role ~= "data_plane" then
        ngx_log(ngx_ERR, "only data_plane can checkout configs")
        return
    end

    local smph = assert(semaphore_new(0))

    kong.worker_events.register(function ()
        smph:post()
    end, "clustering", "control_plane_connected")

    ngx.time.at(0, function (premature)
        if premature then
            return
        end

        if not smph:wait(CP_CONNECT_TIMEOUT) then
            local ok, err = pcall(fetch_config, conf)
            if not ok then
                ngx_log(ngx_ERR, "failed to fetch config: ", err)
            end
        end
    end)
end

function _M.init_worker(conf, role, plugins_list)
    local url = assert(conf.cluster_config_backup_storage)
    local plugin_hash = calculate_hashes(plugins_list)
    if url:sub(1, 5) == "s3://" then
        storage = require("kong.clustering.cfg_sync_backup.s3").new(kong_version, plugin_hash, url)

    else
        ngx_log(ngx_ERR, "unsupported storage: ", url, ". Will not backup config")
    end

    if role == "uploader" then
        uploader()

    elseif role == "downloader" then
        downloader(conf)

    else
        ngx_log(ngx_ERR, "unknown role: ", role)
    end
end

return _M