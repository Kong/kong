-- Copyright (C) Kong Inc.
local BasePlugin  = require "kong.plugins.base_plugin"
local math_random = math.random
local math_floor  = math.floor
local math_fmod   = math.fmod
local crc32       = ngx.crc32_short


local tostring = tostring
local time_now = ngx.now


local log_prefix = "[canary] "
local conf_cache = setmetatable({},{__mode = "k"})


local Canary    = BasePlugin:extend()
Canary.PRIORITY = 13


function Canary:new()
  Canary.super.new(self, "canary")
end


local function get_hash(hash)
  local ctx = ngx.ctx
  local identifier

  if hash == "consumer" then
    -- Consumer is identified id
    identifier = ctx.authenticated_consumer and ctx.authenticated_consumer.id
    if not identifier and ctx.authenticated_credential then
      -- Fallback on credential
      identifier = ctx.authenticated_credential.id
    end
  end

  if not identifier then
    -- remote IP
    identifier = ngx.var.remote_addr
    if not identifier then
      -- Fallback on a random number
      identifier = tostring(math_random())
    end
  end

  return crc32(identifier)
end


local function switch_target(conf)
  -- switch upstream host to the new hostname
  if conf.upstream_target then
    ngx.ctx.balancer_address.host = conf.upstream_target
  end
  -- switch upstream uri to the new uri
  if conf.upstream_uri then
    ngx.var.upstream_uri = conf.upstream_uri
  end
end


function Canary:access(conf)
  Canary.super.access(self)

  local percentage, start, steps, duration = conf.percentage, conf.start,
                                             conf.steps, conf.duration
  local time = time_now()

  local step
  local run_conf = conf_cache[conf]

  if not run_conf then
    run_conf = {}
    conf_cache[conf] = run_conf
    run_conf.prefix = log_prefix  ..
            ((conf.upstream_target ~=nil  and
                    ngx.ctx.balancer_address.host .. "->"
                    .. conf.upstream_target) or "") ..
            ((conf.upstream_uri ~=nil and "uri ->" .. conf.upstream_uri) or "")
    run_conf.step = -1
  end

  if percentage then
    -- fixed percentage canary
    step = percentage * steps / 100

  else
    -- timer based canary
    if time < start then
      -- not started yet, exit
      return
    end

    if time > start + duration then
      -- completely done, switch target

      switch_target(conf)
      return
    end

    -- calculate current step, and hash position. Both 0-indexed.
    step = math_floor((time - start) / duration * steps)
  end

  local hash = math_fmod(get_hash(conf.hash), steps)

  if step ~= run_conf.step then
    run_conf.step = step
    ngx.log(ngx.DEBUG, run_conf.prefix, step, "/", conf.steps)
  end

  if hash <= step then
    switch_target(conf)
  end
end


return Canary
