---
--- mostly copied from resty/dns/balancer/base
--- uses resty/dns/client, hoping to get rid of it
--- and use resty/dns/resolver directly
---
--- the periodic updating keeps a heap of "host"
--- objects.  should be ported to target references
--- or better, subsume the periodicity to the targets themselves
---

local dns_client = require "resty.dns.client"
local resolver = require "resty.dns.resolver"

local kong = kong
local ngx = ngx

local ngx_now = ngx.now
local table_sort = table.sort
local string_format = string.format
local log_DEBUG = kong.log.debug
local log_WARN = kong.log.warn

local SRV_0_WEIGHT = 1      -- SRV record with weight 0 should be hit minimally, hence we replace by 1

local EMPTY = setmetatable({},
  {__newindex = function() error("The 'EMPTY' table is read-only") end})

-- global binary heap for all balancers to share as a single update timer for
-- renewing DNS records
local renewal_heap = require("binaryheap").minUnique()
local renewal_weak_cache = setmetatable({}, { __mode = "v" })
--local renewal_timer  --luacheck: ignore


local client_M = {}



-- define sort order for DNS query results
local sortQuery = function(a,b) return a.__balancerSortKey < b.__balancerSortKey end
local sorts = {
  [resolver.TYPE_A] = function(result)
    local sorted = {}
    -- build table with keys
    for i, v in ipairs(result) do
      sorted[i] = v
      v.__balancerSortKey = v.address
    end
    -- sort by the keys
    table_sort(sorted, sortQuery)
    -- reverse index
    for i, v in ipairs(sorted) do sorted[v.__balancerSortKey] = i end
    return sorted
  end,
  [resolver.TYPE_SRV] = function(result)
    local sorted = {}
    -- build table with keys
    for i, v in ipairs(result) do
      sorted[i] = v
      v.__balancerSortKey = string_format("%06d:%s:%s", v.priority, v.target, v.port)
    end
    -- sort by the keys
    table_sort(sorted, sortQuery)
    -- reverse index
    for i, v in ipairs(sorted) do sorted[v.__balancerSortKey] = i end
    return sorted
  end,
}
sorts[resolver.TYPE_AAAA] = sorts[resolver.TYPE_A] -- A and AAAA use the same sorting order
sorts = setmetatable(sorts,{
    -- all record types not mentioned above are unsupported, throw error
    __index = function(_, key)
      error("Unknown/unsupported DNS record type; "..tostring(key))
    end,
  })


local atomic_tracker = setmetatable({},{ __mode = "k" })
local function assert_atomicity(f, self, ...)
  -- if the following assertion failed, then the function probably yielded and
  -- allowed other threads to enter simultaneously.
  -- This was added to prevent issues like
  -- https://github.com/Kong/lua-resty-dns-client/issues/49
  -- to reappear in the future, providing a clear understanding of what is wrong
  atomic_tracker[self.balancer] = assert(not atomic_tracker[self.balancer],
    "Failed to run atomically, multiple threads updating balancer simultaneously")

  local ok, err = f(self, ...)
  atomic_tracker[self.balancer] = nil

  return ok, err
end


-- Timer invoked to update DNS records
local function resolve_timer_callback()
  local now = ngx_now()
  --print("running timer:",tostring(renewal_heap:peekValue()), " ", now)

  while (renewal_heap:peekValue() or math.huge) < now do
    local key = renewal_heap:pop()
    local host = renewal_weak_cache[key] -- can return nil if GC'ed

    --print("timer on: ",key, " the value is: ", tostring((host or EMPTY).hostname))
    if host then
      log_DEBUG("executing requery for: ", host.hostname)
      host:queryDns(host, false) -- timer-context; cacheOnly always false
    end
  end
end



-- schedules a DNS update for a host in the global timer queue. This uses only
-- a single timer for all balancers.
-- IMPORTANT: this construct should not prevent GC of the Host object
local function schedule_dns_renewal(host)
  local record_expiry = (host.lastQuery or EMPTY).expire or 0
  local key = host.balancer.id .. ":" .. host.hostname .. ":" .. host.port

  -- because of the DNS cache, a stale record will most likely be returned by the
  -- client, and queryDns didn't do anything, other than start a background renewal
  -- query. In that case record_expiry is based on the stale old query (lastQuery)
  -- and it will be in the past. So we schedule a renew at least 0.5 seconds in
  -- the future, so by then the background query is complete and that second call
  -- to queryDns will do the actual updates. Without math.max is would create a
  -- busy loop and hang.
  local new_renew_at = math.max(ngx.now(), record_expiry) + 0.5
  local old_renew_at = renewal_heap:valueByPayload(key)

  -- always store the host in the registry, because the same key might be reused
  -- by a new host-object for the same hostname in case of quick delete/add sequence
  renewal_weak_cache[key] = host

  if old_renew_at then
    renewal_heap:update(key, new_renew_at)
  else
    renewal_heap:insert(new_renew_at, key)
  end
end


-- remove a Host from the DNS renewal timer
local function cancel_dns_renewal(host)
  local key = host.balancer.id .. ":" .. host.hostname .. ":" .. host.port
  renewal_weak_cache[key] = nil
  renewal_heap:remove(key)
end



local function update_dns_result(host, newQuery)
  -- TODO: move most of the datastructure updating to balancer methods
  -- this should be mostly a translation/forwarding procedure
  local balancer = host and host.balancer

  local oldQuery = host.lastQuery or {}
  local oldSorted = host.lastSorted or {}

  -- we're using the dns' own cache to check for changes.
  -- if our previous result is the same table as the current result, then nothing changed
  if oldQuery == newQuery then
    log_DEBUG("no dns changes detected for ", host.hostname)

    return true    -- exit, nothing changed
  end

  -- To detect ttl = 0 we validate both the old and new record. This is done to ensure
  -- we do not hit the edgecase of https://github.com/Kong/lua-resty-dns-client/issues/51
  -- So if we get a ttl=0 twice in a row (the old one, and the new one), we update it. And
  -- if the very first request ever reports ttl=0 (we assume we're not hitting the edgecase
  -- in that case)
  if (newQuery[1] or EMPTY).ttl == 0 and
     (((oldQuery[1] or EMPTY).ttl or 0) == 0 or oldQuery.__ttl0Flag)
  then
    -- ttl = 0 means we need to lookup on every request.
    -- To enable lookup on each request we 'abuse' a virtual SRV record. We set the ttl
    -- to `ttl0Interval` seconds, and set the `target` field to the hostname that needs
    -- resolving. Now `getPeer` will resolve on each request if the target is not an IP address,
    -- and after `ttl0Interval` seconds we'll retry to see whether the ttl has changed to non-0.
    -- Note: if the original record is an SRV we cannot use the dns provided weights,
    -- because we can/are not going to possibly change weights on each request
    -- so we fix them at the `nodeWeight` property, as with A and AAAA records.
    if oldQuery.__ttl0Flag then
      -- still ttl 0 so nothing changed
      oldQuery.touched = ngx_now()
      oldQuery.expire = oldQuery.touched + balancer.ttl0Interval
      log_DEBUG("no dns changes detected for ",
              host.hostname, ", still using ttl=0")
      return true
    end

    log_DEBUG("ttl=0 detected for ", host.hostname)
    newQuery = {
        {
          type = resolver.TYPE_SRV,
          target = host.hostname,
          name = host.hostname,
          port = host.port,
          weight = host.nodeWeight,
          priority = 1,
          ttl = balancer.ttl0Interval,
        },
        expire = ngx_now() + balancer.ttl0Interval,
        touched = ngx_now(),
        __ttl0Flag = true,        -- flag marking this record as a fake SRV one
      }
  end

  -- a new dns record, was returned, but contents could still be the same, so check for changes
  -- sort table in unique order
  local rtype = (newQuery[1] or EMPTY).type
  if not rtype then
    -- we got an empty query table, so assume A record, because it's empty
    -- all existing addresses will be removed
    log_DEBUG("blank dns record for ", host.hostname, ", assuming A-record")
    rtype = resolver.TYPE_A
  end
  local newSorted = sorts[rtype](newQuery)
  local dirty

  if rtype ~= (oldSorted[1] or EMPTY).type then
    -- DNS recordtype changed; recycle everything
    log_DEBUG("dns record type changed for ",
            host.hostname, ", ", (oldSorted[1] or EMPTY).type, " -> ",rtype)
    for i = #oldSorted, 1, -1 do  -- reverse order because we're deleting items
      balancer:disableAddress(host.target, oldSorted[i])
    end
    for _, entry in ipairs(newSorted) do -- use sorted table for deterministic order
      balancer:addAddress(host.target, entry)
    end
    dirty = true
  else
    -- new record, but the same type
    local topPriority = (newSorted[1] or EMPTY).priority -- nil for non-SRV records
    local done = {}
    local dCount = 0
    for _, newEntry in ipairs(newSorted) do
      if newEntry.priority ~= topPriority then break end -- exit when priority changes, as SRV only uses top priority

      local key = newEntry.__balancerSortKey
      local oldEntry = oldSorted[oldSorted[key] or "__key_not_found__"]
      if not oldEntry then
        -- it's a new entry
        log_DEBUG("new dns record entry for ",
                host.hostname, ": ", (newEntry.target or newEntry.address),
                ":", newEntry.port) -- port = nil for A or AAAA records
        balancer:addAddress(host.target, newEntry)     -- TODO: move method to balancer?
        dirty = true
      else
        -- it already existed (same ip, port)
        if newEntry.weight and
           newEntry.weight ~= oldEntry.weight and
           not (newEntry.weight == 0  and oldEntry.weight == SRV_0_WEIGHT)
        then
          -- weight changed (can only be an SRV)
          --host:findAddress(oldEntry):change(newEntry.weight == 0 and SRV_0_WEIGHT or newEntry.weight)
          balancer:changeWeight(host.target, oldEntry, newEntry.weight == 0 and SRV_0_WEIGHT or newEntry.weight)
          dirty = true
        else
          log_DEBUG("unchanged dns record entry for ",
                  host.hostname, ": ", (newEntry.target or newEntry.address),
                  ":", newEntry.port) -- port = nil for A or AAAA records
        end
        done[key] = true
        dCount = dCount + 1
      end
    end
    if dCount ~= #oldSorted then
      -- not all existing entries were handled, remove the ones that are not in the
      -- new query result
      for _, entry in ipairs(oldSorted) do
        if not done[entry.__balancerSortKey] then
          log_DEBUG("removed dns record entry for ",
                  host.hostname, ": ", (entry.target or entry.address),
                  ":", entry.port) -- port = nil for A or AAAA records
          balancer:disableAddress(host.target, entry)
        end
      end
      dirty = true
    end
  end

  host.lastQuery  = newQuery
  host.lastSorted = newSorted

  if dirty then
    -- above we already added and updated records. Removed addresses are disabled, and
    -- need yet to be deleted from the Host
    log_DEBUG("updating balancer based on dns changes for ",
            host.hostname)

    -- allow balancer to update its algorithm
    balancer:afterHostUpdate(host.target)

    -- delete addresses previously disabled
    balancer:deleteDisabledAddresses(host.target)
  end

  log_DEBUG("querying dns and updating for ", host.hostname, " completed")
  return true
end


-- Queries the DNS for this hostname. Updates the underlying address objects.
-- This method always succeeds, but it might leave the balancer in a 0-weight
-- state if none of the hosts resolves.
function client_M.queryDns(host, cacheOnly)
  log_DEBUG("querying dns for ", host.hostname)

  -- first thing we do is the dns query, this is the only place we possibly
  -- yield (cosockets in the dns lib). So once that is done, we're 'atomic'
  -- again, and we shouldn't have any nasty race conditions.
  -- Note: the other place we may yield would be the callbacks, who's content
  -- we do not control, hence they are executed delayed, to ascertain
  -- atomicity.
  local newQuery, err, try_list = dns_client.resolve(host.hostname, nil, cacheOnly)

  if err then
    log_WARN("querying dns for ", host.hostname,
            " failed: ", err , ". Tried ", tostring(try_list))

    -- query failed, create a fake record
    -- the empty record will cause all existing addresses to be removed
    newQuery = {
      expire = ngx_now() + host.interval,
      touched = ngx_now(),
      __dnsError = err,
    }
  end

  assert_atomicity(update_dns_result, host, newQuery)

  schedule_dns_renewal(host)
end


function client_M.init()
  ngx.timer.every(1, resolve_timer_callback)
end


return client_M
