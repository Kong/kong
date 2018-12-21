local singletons = require "kong.singletons"
local balancer = require "kong.runloop.balancer"
local utils = require "kong.tools.utils"
local cjson = require "cjson"


local setmetatable = setmetatable
local tostring = tostring
local ipairs = ipairs
local assert = assert
local table = table


local _TARGETS = {}
local DEFAULT_PORT = 8000


local function sort_targets(a, b)
  if a.created_at < b.created_at then
    return true
  end
  if a.created_at == b.created_at then
    return a.id < b.id
  end
  return false
end


local function clean_history(self, upstream_pk)
  -- when to cleanup: invalid-entries > (valid-ones * cleanup_factor)
  local cleanup_factor = 10

  --cleaning up history, check if it's necessary...
  local targets, err, err_t = self:select_by_upstream_raw(upstream_pk)
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


-- Paginate through the target history for an upstream,
-- including entries that have been since overriden, and those
-- with weight=0 (i.e. the "raw" representation of targets in
-- the database)
function _TARGETS:page_for_upstream_raw(upstream_pk, ...)
  return self.super.page_for_upstream(self, upstream_pk, ...)
end


-- Return the entire target history for an upstream,
-- including entries that have been since overriden, and those
-- with weight=0 (i.e. the "raw" representation of targets in
-- the database)
function _TARGETS:select_by_upstream_raw(upstream_pk, ...)
  local targets = {}

  -- Note that each_for_upstream is not overridden, so it returns "raw".
  for target, err, err_t in self:each_for_upstream(upstream_pk, ...) do
    if not target then
      return nil, err, err_t
    end

    table.insert(targets, target)
  end

  table.sort(targets, sort_targets)

  return targets
end


-- Paginate through targets for an upstream, returning only the
-- latest state of each active (weight>0) target.
function _TARGETS:page_for_upstream(upstream_pk, size, offset, options)
  -- We need to read all targets, then filter the history, then
  -- extract the page requested by the user.

  -- Read all targets; this returns the target history sorted chronologically
  local targets, err, err_t = self:select_by_upstream_raw(upstream_pk, nil, options)
  if not targets then
    return nil, err, err_t
  end

  local all_active_targets = {}
  local seen = {}
  local len = 0

  -- Read the history in reverse order, to obtain the most
  -- recent state of each target.
  for i = #targets, 1, -1 do
    local entry = targets[i]
    if not seen[entry.target] then
      if entry.weight == 0 then
        seen[entry.target] = true

      else
        -- add what we want to send to the client in our array
        len = len + 1
        all_active_targets[len] = entry

        -- track that we found this host:port so we only show
        -- the most recent active one
        seen[entry.target] = true
      end
    end
  end

  -- Extract the requested page
  local page = setmetatable({}, cjson.empty_array_mt)
  size = math.min(size or 100, 1000)
  offset = offset or 0
  for i = 1 + offset, size + offset do
    local target = all_active_targets[i]
    if not target then
      break
    end
    table.insert(page, target)
  end

  local next_offset
  if all_active_targets[size + offset + 1] then
    next_offset = tostring(size + offset)
  end

  return page, nil, nil, next_offset
end


-- Paginate through targets for an upstream, returning only the
-- latest state of each active (weight>0) target, and include
-- health information to the returned records.
function _TARGETS:page_for_upstream_with_health(upstream_pk, ...)
  local targets, err, err_t, next_offset = self:page_for_upstream(upstream_pk, ...)
  if not targets then
    return nil, err, err_t
  end

  local health_info
  health_info, err = balancer.get_upstream_health(upstream_pk.id)
  if err then
    ngx.log(ngx.ERR, "failed getting upstream health: ", err)
  end

  for _, target in ipairs(targets) do
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

  return targets, nil, nil, next_offset
end


function _TARGETS:select_by_upstream_filter(upstream_pk, filter, options)
  assert(filter.id or filter.target)

  local targets, err, err_t = self:select_by_upstream_raw(upstream_pk, nil, options)
  if not targets then
    return nil, err, err_t
  end
  if filter.id then
    for _, t in ipairs(targets) do
      if t.id == filter.id then
        return t
      end
    end
    local err_t = self.errors:not_found(filter.id)
    return nil, tostring(err_t), err_t
  end

  for _, t in ipairs(targets) do
    if t.target == filter.target then
      return t
    end
  end
  err_t = self.errors:not_found_by_field({ target = filter.target })
  return nil, tostring(err_t), err_t
end


function _TARGETS:post_health(upstream, target, is_healthy)
  local addr = utils.normalize_ip(target.target)
  local ip   = utils.format_host(addr.host)
  local port = addr.port
  local _, err = balancer.post_health(upstream, ip, port, is_healthy)
  if err then
    return nil, err
  end

  local health = is_healthy and 1 or 0
  local packet = ("%s|%d|%d|%s|%s"):format(ip, port, health,
                                           upstream.id,
                                           upstream.name)

  singletons.cluster_events:broadcast("balancer:post_health", packet)

  return true
end


return _TARGETS
