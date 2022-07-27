-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

-- Copyright (C) Kong Inc.
local groups = require "kong.plugins.canary.groups"
local meta = require "kong.meta"

local balancer    = require "kong.runloop.balancer"
local utils       = require "kong.tools.utils"
local math_random = math.random
local math_floor  = math.floor
local math_fmod   = math.fmod
local crc32       = ngx.crc32_short
local time_now    = ngx.now

local hostname_type = utils.hostname_type
local get_consumer_id = groups.get_current_consumer_id
local NGX_DEBUG = ngx.DEBUG


local log_prefix = "[canary] "
local conf_cache = setmetatable({},{__mode = "k"})

local CANARY_BY_HEADER_NEVER = "never" -- never go to canary
local CANARY_BY_HEADER_ALWAYS = "always" -- always go to canary

local Canary = {
  PRIORITY = 20,
  VERSION  = meta.core_version
}

local hashing  -- need a forward declaration here
hashing = {
  consumer = function(conf)
    local identifier = get_consumer_id()
    -- return hash, or fall back on IP based hash if no credential
    return identifier and crc32(identifier) or hashing.ip(conf.steps)
  end,
  header = function(conf)
    local identifier = kong.request.get_header(conf.hash_header)
    -- return hash, or fall back on IP based hash if no credential
    return identifier and crc32(identifier) or hashing.ip(conf.steps)
  end,
  ip = function(conf)
    -- remote IP
    local identifier = ngx.var.remote_addr
    -- return hash, or fall back on random if no ip
    return identifier and crc32(identifier) or hashing.none(conf.steps)
  end,
  none = function(conf)
    return math_random(conf.steps) - 1  -- 0 indexed
  end,
}


local function switch_target(host, port, uri)
  local ba = ngx.ctx.balancer_data
  -- switch upstream host to the new hostname
  if host then
    ba.host = host
    ba.type = hostname_type(host)
  end
  -- switch upstream port to the new port number
  if port then
    ba.port = port
  end
  -- switch upstream uri to the new uri
  if uri then
    ngx.var.upstream_uri = uri
  end
end


local function hash_based(conf)
  local host = conf.upstream_host
  local port = conf.upstream_port
  local uri = conf.upstream_uri
  local percentage = conf.percentage
  local start = conf.start
  local steps = conf.steps
  local duration = conf.duration
  local last_step = -1
  local prefix = log_prefix  ..
      ((conf.upstream_host ~= nil and ngx.ctx.balancer_data.host .. "->"
                    .. conf.upstream_host) or "") ..
      ((conf.upstream_uri ~= nil and "uri ->" .. conf.upstream_uri) or "")

  return function()
    local step
    if percentage then
      -- fixed percentage canary
      step = percentage * steps / 100 - 1  -- minus 1 for 0-indexed

    else
      -- timer based canary
      local time = time_now()
      if time < start then
        -- not started yet, exit
        return
      end

      if time > start + duration then
        -- completely done, switch target
        return switch_target(host, port, uri)
      end

      -- calculate current step, and hash position. Both 0-indexed.
      step = math_floor((time - start) / duration * steps)
    end

    local hash = math_fmod(hashing[conf.hash](conf), steps)

    if last_step ~= step then
      last_step = step
      ngx.log(ngx.DEBUG, prefix, step, "/", steps)
    end

    if hash > step then
      -- nothing to do
      return
    end
    -- switch target
    switch_target(host, port, uri)
  end
end

local function list_based(conf)
  local host = conf.upstream_host
  local port = conf.upstream_port
  local uri = conf.upstream_uri
  local switch_on = conf.hash == "allow"
  local canary_croups = conf.groups or {}

  return function()
    local in_group
    local consumer_id = get_consumer_id()
    if not consumer_id then
      in_group = false  -- no consumer ID, so always false
    else
      local err
      in_group, err = groups.consumer_id_in_groups(canary_croups, consumer_id)
      if in_group == nil then
        return error(log_prefix .. "failed to get groups for consumer " ..
                     tostring(consumer_id) .. ": " .. tostring(err))
      end
    end
    if switch_on == in_group then
      -- switch target
      switch_target(host, port, uri)
    end
  end
end


local function upstream_healthy(host, port)
  local ok, _, errcode = balancer.execute {
    type = hostname_type(host),
    host = host,
    port = port,
    try_count = 0,
    tries = {},
  }
  return not (not ok and errcode >= 500)
end

function Canary:access(conf)

  if conf.canary_by_header_name then
    local header = kong.request.get_header(conf.canary_by_header_name)
    if header == CANARY_BY_HEADER_ALWAYS then
      -- use the canary
      return switch_target(conf.upstream_host, conf.upstream_port, conf.upstream_uri)
    elseif header == CANARY_BY_HEADER_NEVER then
      -- return and use original target
      return
    end
  end

  if conf.upstream_fallback and not upstream_healthy(conf.upstream_host,
                                                     conf.upstream_port) then
    ngx.log(NGX_DEBUG, log_prefix, "canary upstream is unhealthy, not switching to it")
    return
  end

  local exec = conf_cache[conf]
  if not exec then
    if conf.hash == "allow" or conf.hash == "deny" then
      exec = list_based(conf)
    else
      exec = hash_based(conf)
    end
    conf_cache[conf] = exec
  end

  exec()

end


return Canary
