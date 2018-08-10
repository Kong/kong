local cjson = require "cjson"
local balancer = require "kong.runloop.balancer"
local utils = require "kong.tools.utils"

local _TARGETS = {}

local DEFAULT_PORT = 8000


local function sort_by_reverse_order(a, b)
  return a.order > b.order
end


local function sort_by_order(a, b)
  return a.order < b.order
end


local function add_order(targets, sort_function)
  for _,target in ipairs(targets) do
    target.order = string.format("%d:%s",
                                 target.created_at * 1000,
                                 target.id)
  end
  table.sort(targets, sort_function)
end


local function clean_history(self, upstream_pk)
  -- when to cleanup: invalid-entries > (valid-ones * cleanup_factor)
  local cleanup_factor = 10

  --cleaning up history, check if it's necessary...
  local targets, err, err_t = self:for_upstream_sorted(upstream_pk)
  if not targets then
    return nil, err, err_t
  end

  -- do clean up
  local cleaned = {}
  local delete = {}

  for _, entry in ipairs(targets) do
    if cleaned[entry.target] then
      -- we got a newer entry for this target than this, so this one can go
      delete[#delete+1] = entry

    else
      -- haven't got this one, so this is the last one for this target
      cleaned[entry.target] = true
      cleaned[#cleaned+1] = entry
      if entry.weight == 0 then
        delete[#delete+1] = entry
      end
    end
  end

  -- do we need to cleanup?
  -- either nothing left, or when 10x more outdated than active entries
  if (#cleaned == 0 and #delete > 0) or
     (#delete >= (math.max(#cleaned,1)*cleanup_factor)) then

    ngx.log(ngx.NOTICE, "[Target DAO] Starting cleanup of target table for upstream ",
               tostring(upstream_pk.id))
    local cnt = 0
    for _, entry in ipairs(delete) do
      -- notice super - this is real delete (not creating a new entity with weight = 0)
      -- not sending update events, one event at the end, based on the
      -- post of the new entry should suffice to reload only once
      self.super.delete(self, { id = entry.id })
      -- ignoring errors here, deleted by id, so should not matter
      -- in case another kong-node does the same cleanup simultaneously
      cnt = cnt + 1
    end

    ngx.log(ngx.INFO, "[Target DAO] Finished cleanup of target table",
      " for upstream ", tostring(upstream_pk.id),
      " removed ", tostring(cnt), " target entries")
  end
end


local function format_target(target)
  local p = utils.normalize_ip(target)
  if not p then
    return false, "Invalid target; not a valid hostname or ip address"
  end
  return utils.format_host(p, DEFAULT_PORT)
end


function _TARGETS:insert(entity)
  if entity.target then
    local formatted_target, err = format_target(entity.target)
    if not formatted_target then
      local err_t = self.errors:schema_violation({ target = err })
      return nil, tostring(err_t), err_t
    end
    entity.target = formatted_target
  end

  clean_history(self, entity.upstream)

  return self.super.insert(self, entity)
end


function _TARGETS:delete(pk)
  local target, err, err_t = self:select(pk)
  if err then
    return nil, err, err_t
  end

  return self:insert({
    target   = target.target,
    upstream = target.upstream,
    weight   = 0,
  })
end


function _TARGETS:delete_by_target(tgt)
  local target, err, err_t = self:select_by_target(tgt)
  if err then
    return nil, err, err_t
  end

  return self:insert({
    target   = target.target,
    upstream = target.upstream,
    weight   = 0,
  })
end


function _TARGETS:for_upstream_raw(upstream_pk, ...)
  return self.super.for_upstream(self, upstream_pk, ...)
end


function _TARGETS:for_upstream_sorted(upstream_pk, ...)
  local targets, err, err_t = self:for_upstream_raw(upstream_pk, ...)
  if not targets then
    return nil, err, err_t
  end
  add_order(targets, sort_by_order)

  return targets
end


function _TARGETS:for_upstream(upstream_pk, ...)
  local targets, err, err_t = self:for_upstream_raw(upstream_pk, ...)
  if not targets then
    return nil, err, err_t
  end
  add_order(targets, sort_by_reverse_order)

  local seen           = {}
  local active_targets = setmetatable({}, cjson.empty_array_mt)
  local len            = 0

  for _, entry in ipairs(targets) do
    if not seen[entry.target] then
      if entry.weight == 0 then
        seen[entry.target] = true

      else
        entry.order = nil -- dont show our order key to the client

        -- add what we want to send to the client in our array
        len = len + 1
        active_targets[len] = entry

        -- track that we found this host:port so we only show
        -- the most recent one (kinda)
        seen[entry.target] = true
      end
    end
  end

  return active_targets
end


function _TARGETS:for_upstream_with_health(upstream_pk, ...)
  local active_targets, err, err_t = self:for_upstream(upstream_pk, ...)
  if not active_targets then
    return nil, err, err_t
  end

  local health_info
  health_info, err = balancer.get_upstream_health(upstream_pk.id)
  if err then
    ngx.log(ngx.ERR, "failed getting upstream health: ", err)
  end

  for _, target in ipairs(active_targets) do
    -- In case of DNS errors when registering a target,
    -- that error happens inside lua-resty-dns-client
    -- and the end-result is that it just doesn't launch the callback,
    -- which means kong.runloop.balancer and healthchecks don't get
    -- notified about the target at all. We extrapolate the DNS error
    -- out of the fact that the target is missing from the balancer.
    -- Note that lua-resty-dns-client does retry by itself,
    -- meaning that if DNS is down and it eventually resumes working, the
    -- library will issue the callback and the target will change state.
    target.health = health_info
                   and (health_info[target.target] or "DNS_ERROR")
                   or  "HEALTHCHECKS_OFF"
  end

  return active_targets
end


function _TARGETS:post_health(upstream, target, is_healthy)
  local addr = utils.normalize_ip(target.target)
  local ip, port = utils.format_host(addr.host), addr.port
  local _, err = balancer.post_health(upstream, ip, port, is_healthy)
  if err then
    return nil, err
  end

  local health = is_healthy and 1 or 0
  local packet = ("%s|%d|%d|%s|%s"):format(ip, port, health,
                                           upstream.id,
                                           upstream.name)
  local cluster_events = require("kong.singletons").cluster_events
  cluster_events:broadcast("balancer:post_health", packet)
  return true
end


return _TARGETS
