--------------------------------------------------------------------------
-- Base-balancer.
--
-- The base class for balancers. It implements DNS resolution and fanning
-- out hostnames to addresses. It builds and maintains a tree structure:
--
--   `balancer <1 --- many> hosts <1 --- many> addresses`
--
-- Updating the DNS records is active, meaning that a background task is running
-- to periodically update DNS records when they expire. This only applies to the
-- hostnames added to the balancer, not to any nested DNS records.
--
-- __Weights__
--
-- Weights will be tracked as follows. Since a Balancer has multiple Hosts, and
-- a Host has multiple Addresses. The Host weight will be the sum of all its
-- addresses, and the Balancer weight will be the sum of all Hosts.
-- See `addHost` on how to set the weight for an `address`.
--
-- The weight of each `address` will be the weight provided as `nodeWeight` when adding
-- a `host`. So adding a `host` with weight 20, that resolves to 2 IP addresses, will
-- insert 2 `addresses` each with a weight of 20, totalling the weight of the `host` to
-- 40.
--
-- Exception 1: If the `host` resolves to an SRV record, in which case each
-- `address` gets the weight as specified in the DNS record. In this case the
-- `nodeWeight` property will be ignored.
--
-- Exception 2: If the DNS record for the `host` has a `ttl=0` then the record contents
-- will be ignored, and a single address with the original hostname will be
-- inserted. This address will get a weight assigned of `nodeWeight`.
-- Whenever the balancer hits this address, it will be resolved on the spot, hence
-- honouring the `ttl=0` value.
--
-- __Adding and resolving hosts__
--
-- When adding a host, it will be resolved and for each entry an `address` will be
-- added. With the exception of a `ttl=0` setting as noted above. When resolving the
-- names, any CNAME records will be dereferenced immediately, any other records
-- will not.
--
-- _Example 1: add an IP address "127.0.0.1"_
--
-- The host object will resolve the name, and since it's and IP address it
-- returns a single A record with 1 entry, that same IP address.
--
--    host object 1   : hostname="127.0.0.1"  --> since this is the name added
--    address object 1: ip="127.0.0.1"        --> single IP address
--
-- _Example 2: complex DNS lookup chain_
--
-- assuming the following lookup chain for a `host` added by name `"myhost"`:
--
--    myhost    --> CNAME yourhost
--    yourhost  --> CNAME herhost
--    herhost   --> CNAME theirhost
--    theirhost --> SRV with 2 entries: host1.com, host2.com
--    host1.com --> A with 1 entry: 192.168.1.10
--    host2.com --> A with 1 entry: 192.168.1.11
--
-- Adding a host by name `myhost` will first create a `host` by name `myhost`. It will then
-- resolve the name `myhost`, the CNAME chain will be dereferenced immediately, so the
-- result will be an SRV record with 2 named entries. The names will be used for the
-- addresses:
--
--    host object 1   : hostname="myhost"
--    address object 1: ip="host1.com"  --> NOT an ip, but a name!
--    address object 2: ip="host2.com"  --> NOT an ip, but a name!
--
-- When the balancer hits these addresses (when calling `getPeer`), it will
-- dereference them (so they will be resolved at balancer-runtime, not at
-- balancer-buildtime).
--
-- There is another special case, in case a record has a ttl=0 setting. In that case
-- a "fake" SRV record is inserted, to make sure we honour the ttl=0 and resolve
-- on each `getPeer` invocation, without altering the balancer every time.
-- Here's an example:
--
--    myhost    --> A with 1 entry: 192.168.1.10, and TTL=0
--
-- Internally it is converted into a fake SRV record which results in the following
-- balancer structure:
--
--    host object 1   : hostname="myhost"
--    address object 1: ip="myhost"  --> NOT an ip, but a name!
--
-- This in turn will result in DNS resolution on each call for an IP, and hence will
-- make sure the ttl=0 setting is effectively being used.
--
-- __Handle management__
--
-- handles are used to retain state between consecutive invocations (calls to
-- the `objBalancer:getPeer` method). The handles are re-used and tracked for
-- garbage collection. There are two uses:
--
--  1. tracking progress (eg. keeping a retry count)
--  2. tracking resources (eg. with least connections a handle 'owns' 1
--  connection, to be released when the connection is finished)
--
-- The basic flow and related responsibilities:
--
--  - user code calls `getPeer` to get an ip/port/hostname according to the load
--  balancing algorithm.
--  - `getPeer` both takes a handle (on a retry), and returns it (on success).
--  - handles are managed by the base balancer, and `getPeer` can call
--  `objBalancer:getHandle` to get one.
--  - on a retry `getPeer` should call `objAddress:release(handle, ignore)` to release
--  the previous (failed) try, and it should clear the `handle.address` field.
--  - on success `getPeer` should set `handle.address` with the address object that
--  returned the ip, port, and hostname, and return the handle with those.
--  - at the end of the connection life cycle the user code should call
--  `handle:release` to release the resources, and/or collect necessary
--  statistics.
--  - as a safety check the handles will have a GC method attached. So in case
--  they are not explicitly released the (default) GC handler will call
--  `handle.address:release(handle, true)` to make sure no resources leak.
--
--
-- __Clustering__
--
-- The base-balancer is deterministic in the way it adds/removes elements. So
-- as long as the confguration is the same, and adding/removing hosts is done
-- in the same order the exact same balancer will be created. This is important
-- in case of consistent-hashing approaches, since each cluster member needs to
-- behave the same.
--
-- _NOTE_: there is one caveat, DNS resolution is not deterministic, because timing
-- differences might cause different orders of adding/removing. Hence the structures
-- can potentially slowly diverge. If this is unacceptable, make sure you do not
-- invlove DNS by adding hosts by their IP adresses instead of their hostname.
--
-- __Housekeeping__
--
-- The balancer does some house keeping and may insert
-- some extra fields in dns records. Those fields will have an `__` prefix
-- (double underscores).
--
-- @author Thijs Schreijer
-- @copyright 2016-2020 Kong Inc. All rights reserved.
-- @license Apache 2.0


local DEFAULT_WEIGHT = 10   -- default weight for a host, if not provided
local DEFAULT_PORT = 80     -- Default port to use (A and AAAA only) when not provided
local TTL_0_RETRY = 60      -- Maximum life-time for hosts added with ttl=0, requery after it expires
local REQUERY_INTERVAL = 30 -- Interval for requerying failed dns queries
local SRV_0_WEIGHT = 1      -- SRV record with weight 0 should be hit minimally, hence we replace by 1

local dns_client = require "resty.dns.client"
local dns_utils = require "resty.dns.utils"
local dns_handle = require "resty.dns.balancer.handle"
local resty_timer = require "resty.timer"
local time = ngx.now
local table_sort = table.sort
local table_remove = table.remove
local table_concat = table.concat
local math_floor = math.floor
local string_format = string.format
local ngx_log = ngx.log
local ngx_DEBUG = ngx.DEBUG
local ngx_WARN = ngx.WARN
local balancer_id_counter = 0

local EMPTY = setmetatable({},
  {__newindex = function() error("The 'EMPTY' table is read-only") end})

local errors = setmetatable({
  ERR_DNS_UPDATED = "Cannot get peer, a DNS update changed the balancer structure, please retry",
  ERR_ADDRESS_UNAVAILABLE = "Address is marked as unavailable",
  ERR_NO_PEERS_AVAILABLE = "No peers are available",
  ERR_BALANCER_UNHEALTHY = "Balancer is unhealthy",
}, {
  __index = function(self, key)
    error("invalid key: " .. tostring(key))
  end
})


local _balancers = setmetatable({}, { __mode = "k" })
local _expire_records_timer = nil

local _M = {}


-- Address object metatable to use for inheritance
local objAddr = {}
local mt_objAddr = { __index = objAddr }
local objHost = {}
local mt_objHost = { __index = objHost }
local objBalancer = {}
local mt_objBalancer = { __index = objBalancer }

local function check_for_expired_records()
  for balancer in pairs(_balancers) do
    --check all hosts for expired records,
    --including those with errors
    --we update, so changes on the list while traversing can happen, keep track of that
    for _, host in ipairs(balancer.hosts) do
      -- only retry the errored ones
      if ((host.lastQuery or EMPTY).expire or 0) < time() then
        ngx_log(ngx_DEBUG, balancer.log_prefix, "executing requery for: ", host.hostname)
        host:queryDns(false) -- timer-context; cacheOnly always false
      end
    end
  end
end

------------------------------------------------------------------------------
-- Implementation properties.
-- These properties are only relevant for implementing a new balancer algorithm
-- using this base class. To use a balancer see the _User properties_ section.
-- @section implementation


-- ===========================================================================
-- address object.
-- Manages an ip address. It is generated by resolving a `host`, hence a single
-- `host` can have multiple `addresses` associated.
-- ===========================================================================

-- Returns the peer info.
-- @return ip-address, port and hostheader for the target, or nil+err if unavailable
-- or lookup error
function objAddr:getPeer(cacheOnly)
  if not self.available then
    return nil, errors.ERR_ADDRESS_UNAVAILABLE
  end

  -- check with our Host whether the DNS record is still up to date
  if not self.host:addressStillValid(cacheOnly, self) then
    -- DNS expired, and this address was removed
    return nil, errors.ERR_DNS_UPDATED
  end

  if self.ipType == "name" then
    -- SRV type record with a named target
    local ip, port, try_list = self.host.balancer.dns.toip(self.ip, self.port, cacheOnly)
    if not ip then
      port = tostring(port) .. ". Tried: " .. tostring(try_list)
      return ip, port
    end

    return ip, port, self.hostHeader
  end

  return self.ip, self.port, self.hostHeader
end

-- disables an address object from the balancer.
-- It will set its weight to 0, and the `disabled` flag to `true`.
-- @see delete
function objAddr:disable()
  ngx_log(ngx_DEBUG, self.log_prefix, "disabling address: ", self.ip, ":", self.port,
          " (host ", (self.host or EMPTY).hostname, ")")

  -- weight to 0; effectively disabling it
  self:change(0)
  self.disabled = true
end

-- Cleans up an address object.
-- The address must have been disabled before.
-- @see disable
function objAddr:delete()
  assert(self.disabled, "Cannot delete an address that wasn't disabled first")
  ngx_log(ngx_DEBUG, self.log_prefix, "deleting address: ", self.ip, ":", self.port,
          " (host ", (self.host or EMPTY).hostname, ")")

  self.host.balancer:callback("removed", self, self.ip,
                              self.port, self.host.hostname, self.hostHeader)
  self.host.balancer:removeAddress(self)
  self.host = nil
end

-- Changes the weight of an address.
function objAddr:change(newWeight)
  ngx_log(ngx_DEBUG, self.log_prefix, "changing address weight: ", self.ip, ":", self.port,
          "(host ", (self.host or EMPTY).hostname, ") ",
          self.weight, " -> ", newWeight)

  self.host:addWeight(newWeight - self.weight)
  if not self.available then
    self.host:addUnavailableWeight(newWeight - self.weight)
  end

  self.weight = newWeight
end

-- Set the availability of the address.
function objAddr:setState(available)
  available = not not available -- force to boolean
  local old_state = self.available

  if old_state == available then
    return  -- no state change
  end

  -- state changed
  self.available = available
  if available then
    self.host:addUnavailableWeight(-self.weight)
  else
    self.host:addUnavailableWeight(self.weight)
  end
end

-- Release any connection resources or record statistics.
-- This method is called from:
--
--  - `objBalancer:getPeer` on a retry (at least it should!, to release anything
--    from the previous attempt).
--  - `objBalancer:release` when called explicitly, by user code.
--  - `objBalancer:release` when called implicitly through the default GC handler
--    (see `objBalancer:getHandle` to provide your custom GC handler)
--
-- @param handle the `handle` as returned by `getPeer`.
-- @param ignore if truthy, indicate to ignore collected statistics
function objAddr:release(handle, ignore)
end


-- Returns the status of the address, bubbles up to `objBalancer:getStatus`
function objAddr:getStatus()
  return {
    ip = self.ip,
    port = self.port,
    weight = self.weight,
    healthy = self.available,
  }
end


--- Creates a new address object. There is no need to call this from user code.
-- When implementing a new balancer algorithm, you might want to override this method.
-- The `addr` table should contain:
--
-- - `ip`: the upstream ip address or target name
-- - `port`: the upstream port number
-- - `weight`: the relative weight for the balancer algorithm
-- - `host`: the host object the new address belongs to
-- @param addr table to be transformed to Address object
-- @return new address object, or error on bad input
function objBalancer:newAddress(addr)
  assert(type(addr.ip) == "string", "Expected 'ip' to be a string, got: " .. type(addr.ip))
  assert(type(addr.port) == "number", "Expected 'port' to be a number, got: " .. type(addr.port))
  assert(addr.port > 0 and addr.port < 65536, "Expected 'port` to be between 0 and 65536, got: " .. addr.port)
  assert(type(addr.weight) == "number", "Expected 'weight' to be a number, got: " .. type(addr.weight))
  assert(addr.weight >= 0, "Expected 'weight' to be equal or greater than 0, got: " .. addr.weight)
  assert(type(addr.host) == "table", "Expected 'host' to be a table, got: " .. type(addr.host))
  assert(getmetatable(addr.host) == mt_objHost, "Expected 'host' to be an objHost type")

  addr = setmetatable(addr, mt_objAddr)
  addr.super = objAddr
  addr.ipType = dns_utils.hostnameType(addr.ip)  -- 'ipv4', 'ipv6' or 'name'
  addr.log_prefix = addr.host.log_prefix
  addr.available = true      -- is this target available?
  addr.disabled = false      -- has this record been disabled? (before deleting)

  addr.host:addWeight(addr.weight)

  if addr.host.nameType ~= "name" then
    -- hostname is an IP address
    addr.hostHeader = nil
  else
    -- hostname is an actual name
    if addr.ipType ~= "name" then
      -- the address is an ip, so use the hostname as header value
      addr.hostHeader = addr.host.hostname
    else
      -- the address itself is a nested name (SRV)
      if addr.useSRVname then
        addr.hostHeader = addr.ip
      else
        addr.hostHeader = addr.host.hostname
      end
    end
  end

  ngx_log(ngx_DEBUG, addr.host.log_prefix, "new address for host '", addr.host.hostname,
          "' created: ", addr.ip, ":", addr.port, " (weight ", addr.weight,")")

  addr.host.balancer:addAddress(addr)
  return addr
end


-- ===========================================================================
-- Host object.
-- Manages a single hostname, with DNS resolution and expanding into
-- multiple `address` objects.
-- ===========================================================================

-- define sort order for DNS query results
local sortQuery = function(a,b) return a.__balancerSortKey < b.__balancerSortKey end
local sorts = {
  [dns_client.TYPE_A] = function(result)
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
  [dns_client.TYPE_SRV] = function(result)
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
sorts[dns_client.TYPE_AAAA] = sorts[dns_client.TYPE_A] -- A and AAAA use the same sorting order
sorts = setmetatable(sorts,{
    -- all record types not mentioned above are unsupported, throw error
    __index = function(self, key)
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


local function update_dns_result(self, newQuery, dns)
  local oldQuery = self.lastQuery or {}
  local oldSorted = self.lastSorted or {}

  -- we're using the dns' own cache to check for changes.
  -- if our previous result is the same table as the current result, then nothing changed
  if oldQuery == newQuery then
    ngx_log(ngx_DEBUG, self.log_prefix, "no dns changes detected for ", self.hostname)

    return true    -- exit, nothing changed
  end

  -- To detect ttl = 0 we validate both the old and new record. This is done to ensure
  -- we do not hit the edgecase of https://github.com/Kong/lua-resty-dns-client/issues/51
  -- So if we get a ttl=0 twice in a row (the old one, and the new one), we update it. And
  -- if the very first request ever reports ttl=0 (we assume we're not hitting the edgecase
  -- in that case)
  if (newQuery[1] or EMPTY).ttl == 0 and
     (((oldQuery[1] or EMPTY).ttl or 0) == 0 or oldQuery.__ttl0Flag) then
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
      oldQuery.touched = time()
      oldQuery.expire = oldQuery.touched + self.balancer.ttl0Interval
      ngx_log(ngx_DEBUG, self.log_prefix, "no dns changes detected for ",
              self.hostname, ", still using ttl=0")
      return true
    end

    ngx_log(ngx_DEBUG, self.log_prefix, "ttl=0 detected for ",
            self.hostname)
    newQuery = {
        {
          type = dns.TYPE_SRV,
          target = self.hostname,
          name = self.hostname,
          port = self.port,
          weight = self.nodeWeight,
          priority = 1,
          ttl = self.balancer.ttl0Interval,
        },
        expire = time() + self.balancer.ttl0Interval,
        touched = time(),
        __ttl0Flag = true,        -- flag marking this record as a fake SRV one
      }
  end

  -- a new dns record, was returned, but contents could still be the same, so check for changes
  -- sort table in unique order
  local rtype = (newQuery[1] or EMPTY).type
  if not rtype then
    -- we got an empty query table, so assume A record, because it's empty
    -- all existing addresses will be removed
    ngx_log(ngx_DEBUG, self.log_prefix, "blank dns record for ",
              self.hostname, ", assuming A-record")
    rtype = dns.TYPE_A
  end
  local newSorted = sorts[rtype](newQuery)
  local dirty

  if rtype ~= (oldSorted[1] or EMPTY).type then
    -- DNS recordtype changed; recycle everything
    ngx_log(ngx_DEBUG, self.log_prefix, "dns record type changed for ",
            self.hostname, ", ", (oldSorted[1] or EMPTY).type, " -> ",rtype)
    for i = #oldSorted, 1, -1 do  -- reverse order because we're deleting items
      self:disableAddress(oldSorted[i])
    end
    for _, entry in ipairs(newSorted) do -- use sorted table for deterministic order
      self:addAddress(entry)
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
        ngx_log(ngx_DEBUG, self.log_prefix, "new dns record entry for ",
                self.hostname, ": ", (newEntry.target or newEntry.address),
                ":", newEntry.port) -- port = nil for A or AAAA records
        self:addAddress(newEntry)
        dirty = true
      else
        -- it already existed (same ip, port)
        if newEntry.weight and
           newEntry.weight ~= oldEntry.weight and
           not (newEntry.weight == 0  and oldEntry.weight == SRV_0_WEIGHT) then
          -- weight changed (can only be an SRV)
          self:findAddress(oldEntry):change(newEntry.weight == 0 and SRV_0_WEIGHT or newEntry.weight)
          dirty = true
        else
          ngx_log(ngx_DEBUG, self.log_prefix, "unchanged dns record entry for ",
                  self.hostname, ": ", (newEntry.target or newEntry.address),
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
          ngx_log(ngx_DEBUG, self.log_prefix, "removed dns record entry for ",
                  self.hostname, ": ", (entry.target or entry.address),
                  ":", entry.port) -- port = nil for A or AAAA records
          self:disableAddress(entry)
        end
      end
      dirty = true
    end
  end

  self.lastQuery = newQuery
  self.lastSorted = newSorted

  if dirty then
    -- above we already added and updated records. Removed addresses are disabled, and
    -- need yet to be deleted from the Host
    ngx_log(ngx_DEBUG, self.log_prefix, "updating balancer based on dns changes for ",
            self.hostname)

    -- allow balancer to update its algorithm
    self.balancer:afterHostUpdate(self)

    -- delete addresses previously disabled
    self:deleteAddresses()
  end

  ngx_log(ngx_DEBUG, self.log_prefix, "querying dns and updating for ", self.hostname, " completed")
  return true
end


-- Queries the DNS for this hostname. Updates the underlying address objects.
-- This method always succeeds, but it might leave the balancer in a 0-weight
-- state if none of the hosts resolves.
-- @return `true`, always succeeds
function objHost:queryDns(cacheOnly)

  ngx_log(ngx_DEBUG, self.log_prefix, "querying dns for ", self.hostname)

  -- first thing we do is the dns query, this is the only place we possibly
  -- yield (cosockets in the dns lib). So once that is done, we're 'atomic'
  -- again, and we shouldn't have any nasty race conditions.
  -- Note: the other place we may yield would be the callbacks, who's content
  -- we do not control, hence they are executed delayed, to ascertain
  -- atomicity.
  local dns = self.balancer.dns
  local newQuery, err, try_list = dns.resolve(self.hostname, nil, cacheOnly)

  if err then
    ngx_log(ngx_WARN, self.log_prefix, "querying dns for ", self.hostname,
            " failed: ", err , ". Tried ", tostring(try_list))

    -- query failed, create a fake record
    -- the empty record will cause all existing addresses to be removed
    newQuery = {
      expire = time() + self.balancer.requeryInterval,
      touched = time(),
      __dnsError = err,
    }
  end

  assert_atomicity(update_dns_result, self, newQuery, dns)

  return true
end


-- Changes the host overall weight. It will also update the parent balancer object.
-- This will be called by the `address` object whenever it changes its weight.
function objHost:addWeight(delta)
  self.weight = self.weight + delta
  self.balancer:addWeight(delta)
end

-- Changes the host overall unavailable weight. It will also update the parent balancer object.
-- This will be called by the `address` object whenever it changes its unavailable weight.
function objHost:addUnavailableWeight(delta)
  self.unavailableWeight = self.unavailableWeight + delta
  self.balancer:addUnavailableWeight(delta)
end

-- Updates the host nodeWeight.
-- @return `true` if something changed that might impact the balancer algorithm
function objHost:change(newWeight)
  local dirty = false
  self.nodeWeight = newWeight
  local lastQuery = self.lastQuery or {}
  if #lastQuery > 0 then
    if lastQuery[1].type == dns_client.TYPE_SRV and not lastQuery.__ttl0Flag then
      -- this is an SRV record (and not a fake ttl=0 one), which
      -- carries its own weight setting, so nothing to update
      ngx_log(ngx_DEBUG, self.log_prefix, "ignoring weight change for ", self.hostname,
              " as SRV records carry their own weight")
    else
      -- so here we have A, AAAA, or a fake SRV, which uses the `nodeWeight` property
      -- go update all our addresses
      for _, addr in ipairs(self.addresses) do
        addr:change(newWeight)
      end
      dirty = true
    end
  end
  return dirty
end

-- Adds an `address` object to the `host`.
-- @param entry (table) DNS entry (single entry, not the full record)
function objHost:addAddress(entry)
  local weight = entry.weight  -- this is nil for anything else than SRV
  if weight == 0 then
    -- Special case: SRV with weight = 0 should be included, but with
    -- the lowest possible probability of being hit. So we force it to
    -- weight 1.
    weight = SRV_0_WEIGHT
  end
  local addresses = self.addresses
  addresses[#addresses + 1] = self.balancer:newAddress {
    ip = entry.address or entry.target,
    port = (entry.port ~= 0 and entry.port) or self.port,
    weight = weight or self.nodeWeight,
    host = self,
    useSRVname = self.balancer.useSRVname,
  }
end

-- Looks up an `address` by a dns entry
-- @param entry (table) DNS entry (single entry, not the full record)
-- @return address object or nil if not found
function objHost:findAddress(entry)
  for _, addr in ipairs(self.addresses) do
    if (addr.ip == (entry.address or entry.target)) and
        addr.port == (entry.port or self.port) then
      -- found it
      return addr
    end
  end
  return -- not found
end

-- Looks up and disables an `address` object from the `host`.
-- @param entry (table) DNS entry (single entry, not the full record)
-- @return address object that was disabled
function objHost:disableAddress(entry)
  local addr = self:findAddress(entry)
  if addr and not addr.disabled then
    addr:disable()
  end
  return addr
end

-- Looks up and deletes previously disabled `address` objects from the `host`.
-- @return `true`
function objHost:deleteAddresses()
  for i = #self.addresses, 1, -1 do -- deleting entries, hence reverse traversal
    if self.addresses[i].disabled then
      self.addresses[i]:delete()
      table_remove(self.addresses, i)
    end
  end

  return true
end

-- disables a host, by setting all adressess to 0
-- Host can only be deleted after updating the balancer algorithm!
-- @return true
function objHost:disable()
  -- set weights to 0
  for _, addr in ipairs(self.addresses) do
    addr:disable()
  end

  return true
end

-- Cleans up a host. Only when its weight is 0.
-- Should only be called after updating the balancer algorithm!
-- @return true or throws an error if weight is non-0
function objHost:delete()
  assert(self.weight == 0, "Cannot delete a host with a non-0 weight")

  for i = #self.addresses, 1, -1 do  -- reverse traversal as we're deleting
    self.addresses[i]:delete()
  end

  self.balancer = nil
end


function objHost:addressStillValid(cacheOnly, address)

  if ((self.lastQuery or EMPTY).expire or 0) < time() and not cacheOnly then
    -- ttl expired, so must renew
    self:queryDns(cacheOnly)

    if (address or EMPTY).host ~= self then
      -- the address no longer points to this host, so it is not valid anymore
      ngx_log(ngx_DEBUG, self.log_prefix, "DNS record for ", self.hostname,
              " was updated and no longer contains the address")
      return false
    end
  end

  return true
end


-- Returns the status of the host, bubbles up to `objBalancer:getStatus`
function objHost:getStatus()
  local dns_source do
    local dns_record = self.lastQuery or EMPTY
    if dns_record.__dnsError then
      dns_source = dns_record.__dnsError

    elseif dns_record.__ttl0Flag then
      dns_source = "ttl=0, virtual SRV"

    elseif dns_record[1] and dns_record[1].type then
      -- regular DNS record, lookup descriptive name from constants
      local rtype = dns_record[1].type
      for k, v in pairs(self.balancer.dns) do
        if tostring(k):sub(1,5) == "TYPE_" and v == rtype then
          dns_source = k:sub(6,-1)
          break
        end
      end

    else
      dns_source = "unknown"
    end
  end

  local addresses = {}
  local status = {
    host = self.hostname,
    port = self.port,
    dns = dns_source,
    nodeWeight = self.nodeWeight,
    weight = {
      total = self.weight,
      unavailable = self.unavailableWeight,
      available = self.weight - self.unavailableWeight,
    },
    addresses = addresses,
  }

  for i = 1,#self.addresses do
    addresses[i] = self.addresses[i]:getStatus()
  end

  return status
end


--- Creates a new host object. There is no need to call this from user code.
-- When implementing a new balancer algorithm, you might want to override this method.
-- The `host` table should have fields:
--
-- - `hostname`: the upstream hostname (as used in dns queries)
-- - `port`: the upstream port number for A and AAAA dns records. For SRV records
--   the reported port by the DNS server will be used.
-- - `nodeWeight`: the relative weight for the balancer algorithm to assign to each A
--   or AAAA dns record. For SRV records the reported weight by the DNS server
--   will be used.
-- - `balancer`: the balancer object the host belongs to
-- @param host table to create the host object from.
-- @return new host object, or error on bad input.
function objBalancer:newHost(host)
  assert(type(host.hostname) == "string", "Expected 'host' to be a string, got: " .. type(host.hostname))
  assert(type(host.port) == "number", "Expected 'port' to be a number, got: " .. type(host.port))
  assert(host.port > 0 and host.port < 65536, "Expected 'port` to be between 0 and 65536, got: " .. host.port)
  assert(type(host.nodeWeight) == "number", "Expected 'nodeWeight' to be a number, got: " .. type(host.nodeWeight))
  assert(host.nodeWeight >= 0, "Expected 'nodeWeight' to be equal or greater than 0, got: " .. host.nodeWeight)
  assert(type(host.balancer) == "table", "Expected 'balancer' to be a table, got: " .. type(host.balancer))
  assert(getmetatable(host.balancer) == mt_objBalancer, "Expected 'balancer' to be an objBalancer type")

  host = setmetatable(host, mt_objHost)
  host.super = objHost
  host.log_prefix = host.balancer.log_prefix
  host.weight = 0            -- overall weight of all addresses within this hostname
  host.unavailableWeight = 0 -- overall weight of unavailable addresses within this hostname
  host.lastQuery = nil       -- last successful dns query performed
  host.lastSorted = nil      -- last successful dns query, sorted for comparison
  host.addresses = {}        -- list of addresses (address objects) this host resolves to
  host.expire = nil          -- time when the dns query this host is based upon expires
  host.nameType = dns_utils.hostnameType(host.hostname)  -- 'ipv4', 'ipv6' or 'name'


  -- insert into our parent balancer before recalculating (in queryDns)
  -- This should actually be a responsibility of the balancer object, but in
  -- this case we do it here, because it is needed before we can redistribute
  -- the indices in the queryDns method just below.
  host.balancer.hosts[#host.balancer.hosts + 1] = host

  ngx_log(ngx_DEBUG, host.balancer.log_prefix, "created a new host for: ", host.hostname)

  host:queryDns()

  return host
end


-- ===========================================================================
-- Balancer object.
-- Manages a set of hostnames, to balance the requests over.
-- ===========================================================================

--- List of addresses.
-- This is a list of addresses, ordered based on when they were added.
-- @field objBalancer.addresses

--- List of hosts.
-- This is a list of addresses, ordered based on when they were added.
-- @field objBalancer.hosts


-- Address iterator.
-- Iterates over all addresses in the balancer (nested through the hosts)
-- @return weight (number), address (address object), host (host object the address belongs to)
function objBalancer:addressIter()
  local host_idx = 1
  local addr_idx = 1
  return function()
    local host = self.hosts[host_idx]
    if not host then return end -- done

    local addr
    while not addr do
      addr = host.addresses[addr_idx]
      if addr then
        addr_idx = addr_idx + 1
        return addr.weight, addr, host
      end
      addr_idx = 1
      host_idx = host_idx + 1
      host = self.hosts[host_idx]
      if not host then return end -- done
    end
  end
end


--- This method is called after changes have been made to the addresses.
--
-- When implementing a new balancer algorithm, you might want to override this method.
--
-- The call is after the addition of new, and disabling old, but before
-- deleting old addresses.
-- The `address.disabled` field will be `true` for addresses that are about to be deleted.
-- @param host the `host` object that had its addresses updated
function objBalancer:afterHostUpdate(host)
end

--- Adds a host to the balancer.
-- The name will be resolved and for each DNS entry an `address` will be added.
--
-- Within a balancer the combination of `hostname` and `port` must be unique, so
-- multiple calls with the same target will only update the `weight` of the
-- existing entry.
-- @param hostname the hostname/ip to add. It will be resolved and based on
-- that 1 or more addresses will be added to the balancer.
-- @param port the port to use for the addresses. If the hostname resolves to
-- an SRV record, this will be ignored, and the port will be taken from the
-- SRV record.
-- @param nodeWeight the weight to use for the addresses. If the hostname
-- resolves to an SRV record, this will be ignored, and the weight will be
-- taken from the SRV record.
-- @return balancer object, or throw an error on bad input
-- @within User properties
function objBalancer:addHost(hostname, port, nodeWeight)
  assert(type(hostname) == "string", "expected a hostname (string), got "..tostring(hostname))
  port = port or DEFAULT_PORT
  nodeWeight = nodeWeight or DEFAULT_WEIGHT
  assert(type(nodeWeight) == "number" and
         math_floor(nodeWeight) == nodeWeight and
         nodeWeight >= 1,
         "Expected 'weight' to be an integer >= 1; got "..tostring(nodeWeight))

  local host
  for _, host_entry in ipairs(self.hosts) do
    if host_entry.hostname == hostname and host_entry.port == port then
      -- found it
      host = host_entry
      break
    end
  end

  if not host then
    -- create the new host, that will insert itself in the balancer
    self:newHost {
      hostname = hostname,
      port = port,
      nodeWeight = nodeWeight,
      balancer = self
    }
  else
    -- this one already exists, update if different
    ngx_log(ngx_DEBUG, self.log_prefix, "host ", hostname, ":", port,
            " already exists, updating weight ",
            host.nodeWeight, "-> ",nodeWeight)

    if host.nodeWeight ~= nodeWeight then
      -- weight changed, go update
      local dirty = host:change(nodeWeight)
      if dirty then
        -- update had an impact so must redistribute indices
        self:afterHostUpdate(host)
      end
    end
  end

  return self
end


--- This method is called after a host is being removed from the balancer.
--
--  When implementing a new balancer algorithm, you might want to override this method.
--
-- The call is after disabling, but before deleting the associated addresses. The
-- address.disabled field will be true for addresses that are about to be deleted.
-- @param host the `host` object about to be deleted
function objBalancer:beforeHostDelete(host)
end


--- This method is called after an address is being added to the balancer.
--
-- When implementing a new balancer algorithm, you might want to override this method.
function objBalancer:onAddAddress(address)
end

function objBalancer:addAddress(address)
  local list = self.addresses
  assert(list[address] == nil, "Can't add address twice")

  self:callback("added", address, address.ip, address.port, address.host.hostname, address.hostHeader)

  list[#list + 1] = address
  self:onAddAddress(address)
end


--- This method is called after an address has been deleted from the balancer.
--
-- When implementing a new balancer algorithm, you might want to override this method.
function objBalancer:onRemoveAddress(address)
end

function objBalancer:removeAddress(address)
  local list = self.addresses

  -- go remove it
  for i, addr in ipairs(list) do
    if addr == address then
      -- found it
      table_remove(list, i)
      self:onRemoveAddress(address)
      return
    end
  end
  error("Address not in the list")
end

--- Removes a host from the balancer. All associated addresses will be
-- deleted, causing updates to the balancer algorithm.
-- Will not throw an error if the hostname is not in the current list.
-- @param hostname hostname to remove
-- @param port port to remove (optional, defaults to 80 if omitted)
-- @return balancer object, or throws an error on bad input
-- @within User properties
function objBalancer:removeHost(hostname, port)
  assert(type(hostname) == "string", "expected a hostname (string), got "..tostring(hostname))
  port = port or DEFAULT_PORT
  for i, host in ipairs(self.hosts) do
    if host.hostname == hostname and host.port == port then

      ngx_log(ngx_DEBUG, self.log_prefix, "removing host ", hostname, ":", port)

      -- set weights to 0
      host:disable()

      -- removing hosts must always be recalculated to make sure
      -- its order is deterministic (only dns updates are not)
      self:beforeHostDelete(host)

      -- remove host
      host:delete()
      table_remove(self.hosts, i)
      break
    end
  end
  return self
end


-- Updates the balancer health status
function objBalancer:updateStatus()
  local old_status = self.healthy

  if self.weight == 0 then
    self.healthy = false
  else
    self.healthy = ((self.weight - self.unavailableWeight) / self.weight * 100 > self.healthThreshold)
  end

  if self.healthy == old_status then
    return -- no status change
  end

  self:callback("health", self.healthy)
end

-- Updates the total weight.
-- @param delta the in/decrease of the overall weight (negative for decrease)
function objBalancer:addWeight(delta)
  self.weight = self.weight + delta
  self:updateStatus()
end

-- Updates the total unavailable weight.
-- @param delta the in/decrease of the overall unavailable weight (negative for decrease)
function objBalancer:addUnavailableWeight(delta)
  self.unavailableWeight = self.unavailableWeight + delta
  self:updateStatus()
end


--- Gets the next ip address and port according to the loadbalancing scheme.
-- If the dns record attached to the requested address is expired, then it will
-- be renewed and as a consequence the balancer algorithm might be updated.
-- @param cacheOnly If truthy, no dns lookups will be done, only cache.
-- @param handle the `handle` returned by a previous call to `getPeer`. This will
-- retain some state over retries. See also `setAddressStatus`.
-- @param hashValue (optional) number for consistent hashing, if supported by
-- the algorithm. The hashValue must be an (evenly distributed) `integer >= 0`.
-- @return `ip + port + hostheader` + `handle`, or `nil+error`
-- @within User properties
-- @usage
-- -- get an IP address
-- local ip, port, hostheader, handle = b:getPeer()
--
-- -- go do the connection stuff here...
--
-- -- on a retry do:
-- ip, port, hostheader, handle = b:getPeer(true, handle)  -- pass in previous 'handle'
--
-- -- go try again
--
-- -- when it finally fails
-- handle:release(true)  -- release resources, but ignore stats
--
-- -- on a successful connection
-- handle:release()  -- release resources, and collect stats
function objBalancer:getPeer(cacheOnly, handle, hashValue)

  error(("Not implemented. cacheOnly: %s hashValue: %s"):format(
      tostring(cacheOnly), tostring(hashValue)))


  --[[ below is just some example code:

  if handle then
    -- existing handle, so it's a retry
    if hashValue then
      -- we have a new hashValue, use it anyway
      handle.hashValue = hashValue
    else
      hashValue = handle.hashValue  -- reuse existing (if any) hashvalue
    end
    handle.retryCount = handle.retryCount + 1
    handle.address:release(handle, true)  -- release any resources
    handle.address = nil -- resources have been released, so prevent GC from kicking in again
  else
    -- no handle, so this is a first try
    handle = self:getHandle()  -- insert GC method if required
    handle.retryCount = 0,
    handle.hashValue = hashValue,
  end

  local address
  while true do
    if self.unhealthy then
      -- we are unhealthy.
      -- This check must be inside the loop, since caling getPeer could
      -- cause a DNS update.
      self:release(handle, true)  -- no address is set, just release handle itself
      return nil, errors.ERR_BALANCER_UNHEALTHY
    end


    -- go and find the next `address` object according to the LB policy
    address = nil


    local ip, port, hostname = address:getPeer(cacheOnly)
    if ip then
      -- success, exit
      handle.address = address
      return ip, port, hostname, handle

    elseif port == errors.ERR_ADDRESS_UNAVAILABLE then
      -- the address was marked as unavailable, keep track here
      -- if all of them fail, then do:
      self:release(handle, true)  -- no address is set, just release handle itself
      return nil, errors.ERR_NO_PEERS_AVAILABLE

    elseif port ~= errors.ERR_DNS_UPDATED then
      -- an unknown error
      self:release(handle, true)  -- no address is set, just release handle itself
      return nil, port
    end

    -- if here, we're going to retry because of an unavailable
    -- peer, or because of a dns update
  end

  -- unreachable   --]]
end


--- Sets the current status of an address.
-- This allows to temporarily suspend peers when they are offline/unhealthy,
-- it will not modify the address held by the record. The parameters passed in should
-- be previous results from `getPeer`.
-- Call this either as:
--
-- - `setAddressStatus(available, address)`,
-- - `setAddressStatus(available, handle)`, or as
-- - `setAddressStatus(available, ip, port, hostname)`
--
-- Using the `address` or `handle` is preferred since it is guaranteed to match. By ip/port/name
-- might fail if there are too many DNS levels.
-- @param available `true` for enabled/healthy, `false` for disabled/unhealthy
-- @param ip_address_handle ip address of the peer, the `address` object, or the `handle`.
-- @param port the port of the peer (in address object, not as recorded with the Host!)
-- @param hostname (optional, defaults to the value of `ip`) the hostname
-- @return `true` on success, or `nil+err` if not found
-- @within User properties
function objBalancer:setAddressStatus(available, ip_address_handle, port, hostname)

  if type(ip_address_handle) == "table" then
    -- it's not an IP
    if ip_address_handle.address then
      -- it's a handle from `setPeer`.
      ip_address_handle.address:setState(available)
    else
      -- it's an address
      ip_address_handle:setState(available)
    end
    return true
  end

  -- no handle, so go and search for it
  hostname = hostname or ip_address_handle
  local name_srv = {}
  for _, addr, host in self:addressIter() do
    if host.hostname == hostname and addr.port == port then
      if addr.ip == ip_address_handle then
        -- found it
        addr:setState(available)
        return true
      elseif addr.ipType == "name" then
        -- so.... the ip is a name. This means that the host that
        -- was added most likely resolved to an SRV, which then has
        -- in turn names as targets instead of ip addresses.
        -- (possibly a fake SRV for ttl=0 records)
        -- Those names are resolved last minute by `getPeer`.
        -- TLDR: we don't track the IP in this case, so we cannot match the
        -- inputs back to an address to disable/enable it.
        -- We record this fact here, and if we have no match in the end
        -- we can provide a more specific message
        name_srv[#name_srv + 1] = addr.ip .. ":" .. addr.port
      end
    end
  end
  local msg = ("no peer found by name '%s' and address %s:%s"):format(hostname, ip_address_handle, tostring(port))
  if name_srv[1] then
    -- no match, but we did find a named one, so making the message more explicit
    msg = msg .. ", possibly the IP originated from these nested dns names: " ..
          table_concat(name_srv, ",")
    ngx_log(ngx_WARN, self.log_prefix, msg)
  end
  return nil, msg
end

--- Sets the status of a host.
-- This will switch all underlying `address` objects to the specified state.
-- @param available `true` for enabled/healthy, `false` for disabled/unhealthy
-- @param hostname name by which it was added to the balancer.
-- @param port the port of the host by which it was added to the balancer (optional, defaults to 80 if omitted).
-- @return `true` on success, or `nil+err` if not found
-- @within User properties
function objBalancer:setHostStatus(available, hostname, port)
  assert(type(hostname) == "string", "expected a hostname (string), got "..tostring(hostname))
  port = port or DEFAULT_PORT
  for _, host in ipairs(self.hosts) do
    if host.hostname == hostname and host.port == port then
      -- got a match, update all it's adresses
      for _, address in ipairs(host.addresses) do
        address:setState(available)
      end
      return true
    end
  end

  return nil, ("No host found by: '%s:%s'"):format(hostname, port)
end


--- Sets an event callback for user code. The callback is invoked for
-- every address added to/removed from the balancer, and on health changes.
--
-- Signature of the callback is for address adding/removing:
--
--   `function(balancer, "added"/"removed", address, ip, port, hostname, hostheader)`
--
-- - `address` is the address object added
-- - `ip` is the IP address for this object, but might also be a hostname if
--   the DNS resolution returns another name (usually in SRV records)
-- - `port` is the port to use
-- - `hostname` is the hostname for which the address was added to the balancer
--   with `addHost` (resolving that name caused the creation of this address)
-- - `hostheader` is the hostheader to be used. This can have 3 values; 1) `nil` if the
--   `hostname` added was an ip-address to begin with, 2) it will be equal to the
--   name in `ip` if there is a named SRV entry, and `useSRVname == true`, 3) otherwise
--   it will be equal to `hostname`
--
-- For health updates the signature is:
--
--   `function(balancer, "health", isHealthy)`
--
-- NOTE: the callback will be executed async (on a timer) so maybe executed
-- only after the methods (`addHost` and `removeHost` for example) have returned.
-- @param callback a function called when an address is added/removed
-- @return `true`, or throws an error on bad input
-- @within User properties
function objBalancer:setCallback(callback)
  assert(type(callback) == "function", "expected a callback function")

  self.callback = function(balancer, action, address, ip, port, hostname, hostheader)
    local ok, err = ngx.timer.at(0, function(premature)
      callback(balancer, action, address, ip, port, hostname, hostheader)
    end)

    if not ok then
      ngx.log(ngx.ERR, self.log_prefix, "failed to create the timer: ", err)
    end
  end

  return true
end


local function default_gc_handler(handle)
  if handle.address then
    handle.address:release(handle, true) -- release connection resources
  end
  -- this is a GC handler, so we're not releasing the handle itself!
  -- It would mean ressurecting it, hence we let it go and don't reuse.
end

local function default_release_handler(handle, ignore)
  if handle.address then
    handle.address:release(handle, ignore) -- release connection resources
  end
  dns_handle.release(handle)  -- release handle itself for reuse
end

--- Gets a handle to be returned by `getPeer`.
-- A handle will have two functions attached to it:
--
-- 1. _the release handler_. This can be called from user code as `handle:release(...)`.
-- The default handler will be `handle:release(ignore)` and will call
-- `handle.address:release(handle, ignore)`, and then release the handle itself, so it
-- can be reused.
--
-- 2. _the GC handler_, which is a fallback in case the handle wasn't released
-- by user code. It will be called as `gc_handler(handle)` and the default
-- implementation will call `handle.address:release(handle, true)`.
--
-- @param gc_handler (optional) a custom GC method for when the handle is
-- not explicitly released.
-- @param release_handler (optional) a custom release method to release the
-- resources when the request cycle is complete.
-- @return handle
function objBalancer:getHandle(gc_handler, release_handler)
  local h = dns_handle.get(gc_handler or default_gc_handler)
  h.release = release_handler or default_release_handler
  return h
end

--- Gets the status of the balancer.
-- This reports the full structure of the balancer state, including hosts,
-- addresses, weights, and availability.
-- @return table with balancer status
-- @within User properties
function objBalancer:getStatus()
  local hosts = {}
  local status = {
    healthy = self.healthy,
    weight = {
      total = self.weight,
      unavailable = self.unavailableWeight,
      available = self.weight - self.unavailableWeight,
    },
    hosts = hosts,
  }

  for i = 1, #self.hosts do
    hosts[i] = self.hosts[i]:getStatus()
  end

  return status
end

--- Creates a new base balancer.
--
-- A single balancer can hold multiple hosts. A host can be an ip address or a
-- name. As such each host can have multiple addresses (or actual ip+port
-- combinations).
--
-- The options table has the following fields;
--
-- - `dns` (required) a configured `dns.client` object for querying the dns server.
-- - `requery` (optional) interval of requerying the dns server for previously
-- failed queries. Defaults to 30 if omitted (in seconds)
-- - `ttl0` (optional) Maximum lifetime for records inserted with `ttl=0`, to verify
-- the ttl is still 0. Defaults to 60 if omitted (in seconds)
-- - `callback` (optional) a function called when an address is added/changed. See
-- `setCallback` for details.
-- - `log_prefix` (optional) a name used in the prefix for log messages. Defaults to
-- `"balancer"` which results in log prefix `"[balancer 1]"` (the number is a sequential
-- id number)
-- - `healthThreshold` (optional) minimum percentage of the balancer weight that must
-- be healthy/available for the whole balancer to be considered healthy. Defaults
-- to 0% if omitted.
-- - `useSRVname` (optional) if truthy, then in case of the hostname resolving to
-- an SRV record with another level of names, the returned hostname by `getPeer` will
-- not be the name of the host as added, but the name of the entry in the SRV
-- record.
-- @param opts table with options
-- @return new balancer object or nil+error
-- @within User properties
_M.new = function(opts)
  assert(type(opts) == "table", "Expected an options table, but got: "..type(opts))
  assert(opts.dns, "expected option `dns` to be a configured dns client")
  assert((opts.requery or 1) > 0, "expected 'requery' parameter to be > 0")
  assert((opts.ttl0 or 1) > 0, "expected 'ttl0' parameter to be > 0")
  assert(type(opts.callback) == "function" or type(opts.callback) == "nil",
    "expected 'callback' to be a function or nil, but got: " .. type(opts.callback))
  assert(type(opts.healthThreshold) == "number" or type(opts.healthThreshold) == "nil",
    "expected 'healthThreshold' to be a number or nil, but got: " .. type(opts.healthThreshold))
  assert((opts.healthThreshold or 1) >= 0 and (opts.healthThreshold or 1) <= 100,
    "expected 'healthThreshold' to be in the range 0-100, but got: " .. tostring(opts.healthThreshold))

  balancer_id_counter = balancer_id_counter + 1
  local self = {
    -- properties
    log_prefix = "[" .. (opts.log_prefix or "balancer") .. " " .. tostring(balancer_id_counter) .. "] ",
    hosts = {},    -- a list a host objects
    addresses = {}, -- a list of addresses, including reverse lookup
    weight = 0,    -- total weight of all hosts
    unavailableWeight = 0,  -- the unavailable weight (range: 0 - weight)
    dns = opts.dns,  -- the configured dns client to use for resolving
    requeryInterval = opts.requery or REQUERY_INTERVAL,  -- how often to requery failed dns lookups (seconds)
    ttl0Interval = opts.ttl0 or TTL_0_RETRY, -- refreshing ttl=0 records
    healthy = false, -- initial healthstatus of the balancer
    healthThreshold = opts.healthThreshold or 0, -- % healthy weight for overall balancer health
    useSRVname = not not opts.useSRVname, -- force to boolean
  }
  self = setmetatable(self, mt_objBalancer)
  self.super = objBalancer

  self:setCallback(opts.callback or function() end) -- callback for address mutations

  _balancers[self] = true
  if not _expire_records_timer then
    local err
    _expire_records_timer, err = resty_timer({
      recurring = true,
      interval = 1, -- check for expired records every 1 second
      detached = true,
      expire = check_for_expired_records,
    })
    if not _expire_records_timer then
      error("failed to create expire records timer for background DNS resolution: " .. err)
    end
  end

  ngx_log(ngx_DEBUG, self.log_prefix, "balancer_base created")
  return self
end

-- export the error constants
_M.errors = errors
objBalancer.errors = errors

return _M
