local singletons = require "kong.singletons"
local balancer = require "kong.runloop.balancer"
local utils = require "kong.tools.utils"
local cjson = require "cjson"
local workspaces   = require "kong.workspaces"


local setmetatable = setmetatable
local tostring = tostring
local ipairs = ipairs
local table = table
local type = type
local min = math.min


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


local function format_target(target)
  local p = utils.normalize_ip(target)
  if not p then
    return false, "Invalid target; not a valid hostname or ip address"
  end
  return utils.format_host(p, DEFAULT_PORT)
end


function _TARGETS:insert(entity, options)
  if entity.target then
    local formatted_target, err = format_target(entity.target)
    if not formatted_target then
      local err_t = self.errors:schema_violation({ target = err })
      return nil, tostring(err_t), err_t
    end
    entity.target = formatted_target
  end

  local workspace = workspaces.get_workspace_id()
  local opts = { nulls = true, workspace = workspace }
  for existent in self:each_for_upstream(entity.upstream, nil, opts) do
    if existent.target == entity.target then
      local err_t = self.errors:unique_violation({ target = existent.target })
      return nil, tostring(err_t), err_t
    end
  end

  return self.super.insert(self, entity, options)
end


function _TARGETS:upsert(pk, entity, options)
  entity.id = pk.id

  if entity.target then
    local formatted_target, err = format_target(entity.target)
    if not formatted_target then
      local err_t = self.errors:schema_violation({ target = err })
      return nil, tostring(err_t), err_t
    end
    entity.target = formatted_target
  end

  -- backward compatibility with Kong older than 2.2.0
  local workspace = workspaces.get_workspace_id()
  local opts = { nulls = true, workspace = workspace }
  for existent in self:each_for_upstream(entity.upstream, nil, opts) do
    if existent.target == entity.target then
      -- if the upserting entity is newer, update
      if entity.created_at > existent.created_at then
        local ok, err, err_t = self.super.delete(self, { id = existent.id }, opts)
        if ok then
          return self.super.insert(self, entity, options)
        end

        return ok, err, err_t
      end
      -- if upserting entity is older, keep the existent entity
      return true

    end
  end

  return self.super.insert(self, entity, options)
end


function _TARGETS:upsert_by_target(unique_key, entity, options)
  entity.target = unique_key
  return self:insert(entity, options)
end


function _TARGETS:select(pk, options)
  local target, err, err_t = self.super.select(self, pk, options)
  if err then
    return nil, err, err_t
  end

  if target then
    local formatted_target, err = format_target(target.target)
    if not formatted_target then
      local err_t = self.errors:schema_violation({ target = err })
      return nil, tostring(err_t), err_t
    end
    target.target = formatted_target
  end
  return target
end


function _TARGETS:delete_by_target(tgt, options)
  local target, err, err_t = self:select_by_target(tgt)
  if err then
    return nil, err, err_t
  end

  return self.super.delete(self, target, options)
end


-- Paginate through the targets for an upstream, including those with
-- weight=0 (i.e. the "raw" representation of targets in the database)
function _TARGETS:page_for_upstream_raw(upstream_pk, ...)
  local page, err, err_t, offset =
    self.super.page_for_upstream(self, upstream_pk, ...)
  if err then
    return nil, tostring(err), err_t
  end

  for _, target in ipairs(page) do
    local formatted_target, err = format_target(target.target)
    if not formatted_target then
      local err_t = self.errors:schema_violation({ target = err })
      return nil, tostring(err_t), err_t
    end
    target.target = formatted_target
  end

  return page, nil, nil, offset
end


-- Return the entire list of targets for an upstream, including entries with
-- weight=0 (i.e. the "raw" representation of targets in the database)
function _TARGETS:select_by_upstream_raw(upstream_pk, options)
  local targets = {}

  -- Note that each_for_upstream is not overridden, so it returns "raw".
  for target, err, err_t in self:each_for_upstream(upstream_pk, nil, options) do
    if not target then
      return nil, err, err_t
    end
    local formatted_target, err = format_target(target.target)
    if not formatted_target then
      local err_t = self.errors:schema_violation({ target = err })
      return nil, tostring(err_t), err_t
    end
    target.target = formatted_target

    table.insert(targets, target)
  end

  table.sort(targets, sort_targets)

  return targets
end


-- Paginate through targets for an upstream, returning only the active
-- (weight>0) target.
function _TARGETS:page_for_upstream(upstream_pk, size, offset, options)
  -- Read all targets
  local targets, err, err_t = self:select_by_upstream_raw(upstream_pk, options)
  if not targets then
    return nil, err, err_t
  end

  local all_active_targets = {}
  local seen = {}
  local len = 0

  for i = #targets, 1, -1 do
    local entry = targets[i]
    if not seen[entry.target] then
      -- add what we want to send to the client in our array
      len = len + 1
      all_active_targets[len] = entry

      -- track that we found this host:port so we only show
      -- the most recent active one
      seen[entry.target] = true
    end
  end

  local pagination = self.pagination

  if type(options) == "table" and type(options.pagination) == "table" then
    pagination = utils.table_merge(pagination, options.pagination)
  end

  if not size then
    size = pagination.page_size
  end

  size = min(size, pagination.max_page_size)
  offset = offset or 0

  -- Extract the requested page
  local page = setmetatable({}, cjson.array_mt)
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

  if health_info then
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
      if health_info[target.target] ~= nil and
        #health_info[target.target].addresses > 0 then
        target.health = "HEALTHCHECKS_OFF"
        -- If any of the target addresses are healthy, then the target is
        -- considered healthy.
        for _, address in ipairs(health_info[target.target].addresses) do
          if address.health == "HEALTHY" then
            target.health = "HEALTHY"
            break
          elseif address.health == "UNHEALTHY" then
            target.health = "UNHEALTHY"
          end

        end
      else
        target.health = "DNS_ERROR"
      end
      target.data = health_info[target.target]
    end

  end

  return targets, nil, nil, next_offset
end


function _TARGETS:select_by_upstream_filter(upstream_pk, filter, options)
  local targets, err, err_t = self:select_by_upstream_raw(upstream_pk, options)
  if not targets then
    return nil, err, err_t
  end

  for i = #targets, 1, -1 do
    local t = targets[i]
    if t.id == filter.id or t.target == filter.target then
      return t
    end
  end
end


function _TARGETS:post_health(upstream_pk, target, address, is_healthy)
  local upstream = balancer.get_upstream_by_id(upstream_pk.id)
  local host_addr = utils.normalize_ip(target.target)
  local hostname = utils.format_host(host_addr.host)
  local ip
  local port

  if address ~= nil then
    local addr = utils.normalize_ip(address)
    ip = addr.host
    if addr.port then
      port = addr.port
    else
      port = DEFAULT_PORT
    end
  else
    ip = nil
    port = host_addr.port
  end

  local _, err = balancer.post_health(upstream, hostname, ip, port, is_healthy)
  if err then
    return nil, err
  end

  local health = is_healthy and 1 or 0
  local packet = ("%s|%s|%d|%d|%s|%s"):format(hostname, ip or "", port, health,
                                           upstream.id,
                                           upstream.name)

  singletons.cluster_events:broadcast("balancer:post_health", packet)

  return true
end


function _TARGETS:get_balancer_health(upstream_pk)
  local health_info, err = balancer.get_balancer_health(upstream_pk.id)
  if err then
    ngx.log(ngx.ERR, "failed getting upstream health: ", err)
  end

  return health_info
end


return _TARGETS
