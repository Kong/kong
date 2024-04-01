local cjson = require("cjson.safe")
local utils = require("kong.dns.utils")
local mlcache = require("kong.resty.mlcache")
local resolver = require("resty.dns.resolver")

local now       = ngx.now
local log       = ngx.log
local ERR       = ngx.ERR
local WARN      = ngx.WARN
local DEBUG     = ngx.DEBUG
local ALERT     = ngx.ALERT
local timer_at  = ngx.timer.at

local pairs           = pairs
local ipairs          = ipairs
local math_min        = math.min
local string_lower    = string.lower
local table_insert    = table.insert
local table_isempty   = require("table.isempty")
local tablex_readonly = require("pl.tablex").readonly

local parse_hosts   = utils.parse_hosts
local ipv6_bracket  = utils.ipv6_bracket
local search_names  = utils.search_names
local get_next_round_robin_answer           = utils.get_next_round_robin_answer
local get_next_weighted_round_robin_answer  = utils.get_next_weighted_round_robin_answer

local req_dyn_hook_run_hooks = require("kong.dynamic_hook").run_hooks


-- Constants and default values

local DEFAULT_ERROR_TTL   = 1     -- unit: second
local DEFAULT_STALE_TTL   = 4
local DEFAULT_EMPTY_TTL   = 30
-- long-lasting TTL of 10 years for hosts or static IP addresses in cache settings
local LONG_LASTING_TTL    = 10 * 365 * 24 * 60 * 60

local PERSISTENT_CACHE_TTL = { ttl = 0 }  -- used for mlcache:set

local DEFAULT_ORDER = { "LAST", "SRV", "A", "AAAA", "CNAME" }

local TYPE_SRV      = resolver.TYPE_SRV
local TYPE_A        = resolver.TYPE_A
local TYPE_AAAA     = resolver.TYPE_AAAA
local TYPE_CNAME    = resolver.TYPE_CNAME
local TYPE_LAST     = -1

local NAME_TO_TYPE = {
  SRV     = TYPE_SRV,
  A       = TYPE_A,
  AAAA    = TYPE_AAAA,
  CNAME   = TYPE_CNAME,
  LAST    = TYPE_LAST,
}

local TYPE_TO_NAME = {
  [TYPE_SRV]      = "SRV",
  [TYPE_A]        = "A",
  [TYPE_AAAA]     = "AAAA",
  [TYPE_CNAME]    = "CNAME",
  [TYPE_LAST]     = "LAST",
}

local HIT_L3 = 3 -- L1 lru, L2 shm, L3 callback, L4 stale

local HIT_LEVEL_TO_NAME = {
  [1] = "hit_lru",
  [2] = "hit_shm",
  [3] = "hit_cb",
  [4] = "hit_stale",
}

-- server replied error from the DNS protocol
local NAME_ERROR_CODE             = 3 -- response code 3 as "Name Error" or "NXDOMAIN"
-- client specific error
local CACHE_ONLY_ERROR_CODE       = 100
local CACHE_ONLY_ERROR_MESSAGE    = "cache only lookup failed"
local CACHE_ONLY_ANSWERS = tablex_readonly({ errcode = CACHE_ONLY_ERROR_CODE, errstr = CACHE_ONLY_ERROR_MESSAGE })
local EMPTY_RECORD_ERROR_CODE     = 101
local EMPTY_RECORD_ERROR_MESSAGE  = "empty record received"


-- APIs

local _M = {
  TYPE_SRV     = TYPE_SRV,
  TYPE_A       = TYPE_A,
  TYPE_AAAA    = TYPE_AAAA,
  TYPE_CNAME   = TYPE_CNAME,
  TYPE_LAST    = TYPE_LAST,
}
local mt = { __index = _M }


local TRIES_MT = { __tostring = cjson.encode, }


local function stats_init_name(stats, name)
  if not stats[name] then
    stats[name] = {}
  end
end


local function stats_increment(stats, name, key)
  stats[name][key] = (stats[name][key] or 0) + 1
end


local function stats_set_count(stats, name, key, value)
  stats[name][key] = value
end


-- lookup or set TYPE_LAST (the DNS record type from the last successful query)
local function insert_last_type(cache, name, qtype)
  local key = "last:" .. name
  if TYPE_TO_NAME[qtype] and cache:get(key) ~= qtype then
    cache:set(key, PERSISTENT_CACHE_TTL, qtype)
  end
end


local function get_last_type(cache, name)
  return cache:get("last:" .. name)
end


local init_hosts do
  local function insert_answer_into_cache(cache, address, name, qtype)
    -- insert via the `:get` callback to prevent inter-process communication
    cache:get(name .. ":" .. qtype, nil, function()
      return {
        ttl = LONG_LASTING_TTL,
        expire = now() + LONG_LASTING_TTL,
        {
          name = name,
          type = qtype,
          address = address,
          class = 1,
          ttl = LONG_LASTING_TTL,
        },
      }, nil, LONG_LASTING_TTL
    end)
  end

  -- insert hosts into cache
  function init_hosts(cache, path, preferred_ip_type)
    local hosts = parse_hosts(path)

    for name, address in pairs(hosts) do
      name = string_lower(name)

      if address.ipv4 then
        insert_answer_into_cache(cache, address.ipv4, name, TYPE_A)
        insert_last_type(cache, name, TYPE_A)
      end

      if address.ipv6 then
        insert_answer_into_cache(cache, address.ipv6, name, TYPE_AAAA)
        if not address.ipv4 or preferred_ip_type == TYPE_AAAA then
          insert_last_type(cache, name, TYPE_AAAA)
        end
      end
    end

    return hosts
  end
end


-- distinguish the worker_events sources registered by different new() instances
local ipc_counter = 0

function _M.new(opts)
  opts = opts or {}

  -- parse resolv.conf
  local resolv, err = utils.parse_resolv_conf(opts.resolv_conf, opts.enable_ipv6)
  if not resolv then
    log(WARN, "Invalid resolv.conf: ", err)
    resolv = { options = {} }
  end

  -- init the resolver options for lua-resty-dns
  local nameservers = (opts.nameservers and not table_isempty(opts.nameservers)) and
                      opts.nameservers or resolv.nameservers
  if not nameservers or table_isempty(nameservers) then
    log(WARN, "Invalid configuration, no nameservers specified")
  end

  local r_opts = {
    retrans     = opts.retrans or resolv.options.attempts or 5,
    timeout     = opts.timeout or resolv.options.timeout or 2000, -- ms
    no_random   = opts.no_random or not resolv.options.rotate,
    nameservers = nameservers,
  }

  -- init the mlcache

  -- maximum timeout for the underlying r:query() operation to complete
  -- socket timeout * retrans * 2 calls for send and receive + 1s extra delay
  local lock_timeout = r_opts.timeout / 1000 * r_opts.retrans * 2 + 1 -- s

  local resty_lock_opts = {
    timeout = lock_timeout,
    exptimeout = lock_timeout + 1,
  }

  -- TODO: convert the ipc a module constant, currently we need to use the
  --       ipc_source to distinguish sources of different DNS client events.
  ipc_counter = ipc_counter + 1
  local ipc_source = "dns_client_mlcache#" .. ipc_counter
  local ipc = {
    register_listeners = function(events)
      -- The DNS client library will be required in globalpatches before Kong
      -- initializes worker_events.
      if not kong or not kong.worker_events then
        return
      end

      local cwid = ngx.worker.id()
      for _, ev in pairs(events) do
        local handler = function(data, event, source, wid)
          if cwid ~= wid then
            ev.handler(data)
          end
        end

        kong.worker_events.register(handler, ipc_source, ev.channel)
      end
    end,

    -- @channel: event channel name, such as "mlcache:invalidate:dns_cache"
    -- @data: mlcache's key name, such as "<qname>:<qtype>"
    broadcast = function(channel, data)
      if not kong or not kong.worker_events then
        return
      end

      local ok, err = kong.worker_events.post(ipc_source, channel, data)
      if not ok then
        log(ERR, "failed to post event '", ipc_source, "', '", channel, "': ", err)
      end
    end,
  }

  local cache, err = mlcache.new("dns_cache", "kong_dns_cache", {
    ipc             = ipc,
    neg_ttl         = opts.empty_ttl or DEFAULT_EMPTY_TTL,
    lru_size        = opts.cache_size or 10000,
    resty_lock_opts = resty_lock_opts,
  })

  if not cache then
    return nil, "could not create mlcache: " .. err
  end

  if opts.cache_purge then
    cache:purge(true)
  end

  -- parse order
  if opts.order and table_isempty(opts.order) then
    return nil, "Invalid order array: empty record types"
  end

  local order = opts.order or DEFAULT_ORDER
  local search_types = {}
  local preferred_ip_type

  for i, typstr in ipairs(order) do
    local qtype = NAME_TO_TYPE[typstr:upper()]
    if not qtype then
      return nil, "Invalid dns record type in order array: " .. typstr
    end

    search_types[i] = qtype

    if (qtype == TYPE_A or qtype == TYPE_AAAA) and not preferred_ip_type then
      preferred_ip_type = qtype
    end
  end

  preferred_ip_type = preferred_ip_type or TYPE_A

  -- parse hosts
  local hosts = init_hosts(cache, opts.hosts, preferred_ip_type)

  return setmetatable({
    cache         = cache,
    stats         = {},
    hosts         = hosts,
    r_opts        = r_opts,
    resolv        = opts._resolv or resolv,
    valid_ttl     = opts.valid_ttl,
    error_ttl     = opts.error_ttl or DEFAULT_ERROR_TTL,
    stale_ttl     = opts.stale_ttl or DEFAULT_STALE_TTL,
    empty_ttl     = opts.empty_ttl or DEFAULT_EMPTY_TTL,
    search_types  = search_types,
    -- quickly accessible constant empty answers
    EMPTY_ANSWERS = tablex_readonly({
      errcode = EMPTY_RECORD_ERROR_CODE,
      errstr  = EMPTY_RECORD_ERROR_MESSAGE,
      ttl     = opts.empty_ttl or DEFAULT_EMPTY_TTL,
    }),
  }, mt)
end


local function process_answers(self, qname, qtype, answers)
  local errcode = answers.errcode
  if errcode then
    answers.ttl = errcode == NAME_ERROR_CODE and self.empty_ttl or self.error_ttl
    return answers
  end

  local processed_answers = {}
  local cname_answer

  local ttl = math_min(self.valid_ttl or 0xffffffff, 0xffffffff)  -- 0xffffffff for maximum TTL value

  for _, answer in ipairs(answers) do
    answer.name = string_lower(answer.name)

    if self.valid_ttl then
      answer.ttl = self.valid_ttl
    else
      ttl = math_min(ttl, answer.ttl)
    end

    if answer.type == TYPE_CNAME then
      cname_answer = answer   -- use the last one as the real cname

    elseif answer.type == qtype then
      -- compatible with balancer, see https://github.com/Kong/kong/pull/3088
      if answer.type == TYPE_AAAA then
        answer.address = ipv6_bracket(answer.address)

      elseif answer.type == TYPE_SRV then
        answer.target = ipv6_bracket(answer.target)
      end

      -- skip the SRV record pointing to itself,
      -- see https://github.com/Kong/lua-resty-dns-client/pull/3
      if not (answer.type == TYPE_SRV and answer.target == qname) then
        table_insert(processed_answers, answer)
      end
    end
  end

  if table_isempty(processed_answers) then
    if not cname_answer then
      return self.EMPTY_ANSWERS
    end

    processed_answers[1] = cname_answer

    log(DEBUG, "processed cname:", cname_answer.cname)

  else
    log(DEBUG, "processed ans:", #processed_answers)
  end

  processed_answers.expire = now() + ttl
  processed_answers.ttl = ttl

  return processed_answers
end


local function resolve_query(self, name, qtype, tries)
  local key = name .. ":" .. qtype
  stats_increment(self.stats, key, "query")

  local r, err = resolver:new(self.r_opts)
  if not r then
    return nil, "failed to instantiate the resolver: " .. err
  end

  local start_time = now()

  local options = { additional_section = true, qtype = qtype }
  local answers, err = r:query(name, options)
  r:destroy()

  local query_time = now() - start_time -- the time taken for the DNS query
  local time_str = ("%.3f %.3f"):format(start_time, query_time)

  stats_set_count(self.stats, key, "query_last_time", time_str)

  log(DEBUG, "r:query() ans:", answers and #answers or "-", " t:", time_str)

  if not answers then
    stats_increment(self.stats, key, "query_fail_nameserver")
    err = err or "unknown"
    return nil, "DNS server error: " .. err .. ", Query Time: " .. time_str
  end

  answers = process_answers(self, name, qtype, answers)

  stats_increment(self.stats, key, answers.errstr and "query_fail:" .. answers.errstr
                                                   or "query_succ")

  return answers, nil, answers.ttl
end


local function stale_update_task(premature, self, key, name, qtype, short_key)
  if premature then
    return
  end

  local answers = resolve_query(self, name, qtype, {})
  if answers and (not answers.errcode or answers.errcode == NAME_ERROR_CODE) then
    self.cache:set(key, { ttl = answers.ttl }, answers)
    insert_last_type(self.cache, name, qtype)

    -- simply invalidate it and let the search iteration choose the correct one
    self.cache:delete(short_key)
  end
end


local function start_stale_update_task(self, key, name, qtype, short_key)
  stats_increment(self.stats, key, "stale")

  local ok, err = timer_at(0, stale_update_task, self, key, name, qtype, short_key)
  if not ok then
    log(ALERT, "failed to start a timer to update stale DNS records: ", err)
  end
end


local function resolve_name_type_callback(self, name, qtype, cache_only, short_key, tries)
  local key = name .. ":" .. qtype

  -- `:peek(stale=true)` verifies if the expired key remains in L2 shm, then
  -- initiates an asynchronous background updating task to refresh it.
  local ttl, _, answers = self.cache:peek(key, true)
  if answers and ttl then
    if not answers.expired then
      answers.expire = now() + ttl
      answers.expired = true
      ttl = ttl + self.stale_ttl

    else
      ttl = ttl + (answers.expire - now())
    end

    -- trigger the update task by the upper caller every 60 seconds
    ttl = math_min(ttl, 60)

    if ttl > 0 then
      log(DEBUG, "start stale update task ", key, " ttl:", ttl)

      -- mlcache's internal lock mechanism ensures concurrent control
      start_stale_update_task(self, key, name, qtype, short_key)
      answers.ttl = ttl
      return answers, nil, ttl
    end
  end

  if cache_only then
    return CACHE_ONLY_ANSWERS, nil, -1
  end

  local answers, err, ttl = resolve_query(self, name, qtype, tries)
  return answers, err, ttl
end


-- detect circular references in DNS CNAME or SRV records
local function detect_recursion(resolved_names, key)
  local detected = resolved_names[key]
  resolved_names[key] = true
  return detected
end


local function resolve_name_type(self, name, qtype, cache_only, short_key, tries, resolved_names)
  local key = name .. ":" .. qtype

  stats_init_name(self.stats, key)

  if detect_recursion(resolved_names, key) then
    stats_increment(self.stats, key, "fail_recur")
    return nil, "recursion detected for name: " .. key
  end

  local answers, err, hit_level = self.cache:get(key, nil,
                                                 resolve_name_type_callback,
                                                 self, name, qtype, cache_only,
                                                 short_key, tries)
  -- check for runtime errors in the callback
  if err and err:sub(1, 8) == "callback" then
    log(ALERT, err)
  end

  log(DEBUG, "cache lookup ", key, " ans:", answers and #answers or "-", " hlv:", hit_level or "-")

  local ctx = ngx.ctx
  if ctx and ctx.has_timing then
    req_dyn_hook_run_hooks("timing", "dns:cache_lookup",
                           (hit_level and hit_level < HIT_L3))
  end

  -- hit L1 lru or L2 shm
  if hit_level and hit_level < HIT_L3 then
    stats_increment(self.stats, key, HIT_LEVEL_TO_NAME[hit_level])
  end

  if err or answers.errcode then
    if not err then
      local src = answers.errcode < CACHE_ONLY_ERROR_CODE and "server" or "client"
      err = ("dns %s error: %s %s"):format(src, answers.errcode, answers.errstr)
    end

    table_insert(tries, { name .. ":" .. TYPE_TO_NAME[qtype], err })
  end

  return answers, err
end


local function get_search_types(self, name, qtype)
  local input_types = qtype and { qtype } or self.search_types
  local checked_types = {}
  local types = {}

  for _, qtype in ipairs(input_types) do
    if qtype == TYPE_LAST then
      qtype = get_last_type(self.cache, name)
    end

    if qtype and not checked_types[qtype] then
      table_insert(types, qtype)
      checked_types[qtype] = true
    end
  end

  return types
end


local function check_and_get_ip_answers(name)
  if name:match("^%d+%.%d+%.%d+%.%d+$") then  -- IPv4
    return {
      { name = name, class = 1, type = TYPE_A, address = name },
    }
  end

  if name:find(":", 1, true) then             -- IPv6
    return {
      { name = name, class = 1, type = TYPE_AAAA, address = ipv6_bracket(name) },
    }
  end

  return nil
end


-- resolve all `name`s and `type`s combinations and return first usable answers
local function resolve_names_and_types(self, name, typ, cache_only, short_key, tries, resolved_names)
  local answers = check_and_get_ip_answers(name)
  if answers then -- domain name is IP literal
    answers.ttl = LONG_LASTING_TTL
    answers.expire = now() + answers.ttl
    return answers, nil, tries
  end

  -- TODO: For better performance, it may be necessary to rewrite it as an
  --       iterative function.
  local types = get_search_types(self, name, typ)
  local names = search_names(name, self.resolv, self.hosts)

  local err
  for _, qtype in ipairs(types) do
    for _, qname in ipairs(names) do
      answers, err = resolve_name_type(self, qname, qtype, cache_only,
                                       short_key, tries, resolved_names)
      -- severe error occurred
      if not answers then
        return nil, err, tries
      end

      if not answers.errcode then
        insert_last_type(self.cache, qname, qtype) -- cache TYPE_LAST
        return answers, nil, tries
      end
    end
  end

  -- not found in the search iteration
  return nil, err, tries
end


local function resolve_all(self, name, qtype, cache_only, tries, resolved_names)
  name = string_lower(name)
  tries = setmetatable(tries or {}, TRIES_MT)

  -- key like "short:example.com:all" or "short:example.com:5"
  local key = "short:" .. name .. ":" .. (qtype or "all")

  stats_init_name(self.stats, name)
  stats_increment(self.stats, name, "runs")

  if detect_recursion(resolved_names, key) then
    stats_increment(self.stats, name, "fail_recur")
    return nil, "recursion detected for name: " .. name
  end

  -- quickly lookup with the key "short:<name>:all" or "short:<name>:<qtype>"
  local answers, err, hit_level = self.cache:get(key)
  if not answers then
    log(DEBUG, "quickly cache lookup ", key, " ans:- hlvl:", hit_level or "-")

    answers, err, tries = resolve_names_and_types(self, name, qtype, cache_only,
                                                  key, tries, resolved_names)
    if not cache_only and answers then
      -- If another worker resolved the name between these two `:get`, it can
      -- work as expected and will not introduce a race condition.

      -- insert via the `:get` callback to prevent inter-process communication
      self.cache:get(key, nil, function()
        return answers, nil, answers.ttl
      end)
    end

    stats_increment(self.stats, name, answers and "miss" or "fail")
  else
    log(DEBUG, "quickly cache lookup ", key, " ans:", #answers, " hlv:", hit_level or "-")

    local ctx = ngx.ctx
    if ctx and ctx.has_timing then
      req_dyn_hook_run_hooks("timing", "dns:cache_lookup",
                             (hit_level and hit_level < HIT_L3))
    end

    stats_increment(self.stats, name, HIT_LEVEL_TO_NAME[hit_level])
  end

  -- dereference CNAME
  if qtype ~= TYPE_CNAME and answers and answers[1].type == TYPE_CNAME then
    stats_increment(self.stats, name, "cname")
    return resolve_all(self, answers[1].cname, qtype, cache_only, tries, resolved_names)
  end

  return answers, err, tries
end


function _M:resolve(name, qtype, cache_only, tries)
  return resolve_all(self, name, qtype, cache_only, tries, {})
end


function _M:resolve_address(name, port, cache_only, tries, resolved_names)
  resolved_names = resolved_names or {}

  local answers, err, tries = resolve_all(self, name, nil, cache_only, tries, resolved_names)
  if not answers then
    return nil, err, tries
  end

  -- non-nil answers and return_random
  if answers[1].type == TYPE_SRV then
    local answer = get_next_weighted_round_robin_answer(answers)
    port = (answer.port ~= 0 and answer.port) or port
    return self:resolve_address(answer.target, port, cache_only, tries, resolved_names)
  end

  return get_next_round_robin_answer(answers).address, port, tries
end


-- compatible with original DNS client library
-- These APIs will be deprecated if fully replacing the original one.
local dns_client

function _M.init(opts)
  opts = opts or {}
  opts.valid_ttl = opts.validTtl
  opts.error_ttl = opts.badTtl
  opts.stale_ttl = opts.staleTtl
  opts.cache_size = opts.cacheSize

  local client, err = _M.new(opts)
  if not client then
    return nil, err
  end

  dns_client = client
  return true
end


-- New and old libraries have the same function name.
_M._resolve = _M.resolve

function _M.resolve(name, r_opts, cache_only, tries)
  return dns_client:_resolve(name, r_opts and r_opts.qtype, cache_only, tries)
end


function _M.toip(name, port, cache_only, tries)
  return dns_client:resolve_address(name, port, cache_only, tries)
end


-- for example, "example.com:33" -> "example.com:SRV"
local function format_key(key)
  local qname, qtype = key:match("([^:]+):(%d+)")  -- match "(qname):(qtype)"
  return qtype and qname .. ":" .. (TYPE_TO_NAME[tonumber(qtype)] or qtype)
               or  key
end


function _M.stats()
  local stats = {}
  for k, v in pairs(dns_client.stats) do
    stats[format_key(k)] = v
  end
  return stats
end


-- For testing

if package.loaded.busted then
  function _M.getobj()
    return dns_client
  end

  function _M.getcache()
    return {
      set = function(self, k, v, ttl)
        self.cache:set(k, {ttl = ttl or 0}, v)
      end,

      delete = function(self, k)
        self.cache:delete(k)
      end,

      cache = dns_client.cache,
    }
  end

  function _M:_insert_last_type(name, qtype)  -- export as different name!
    insert_last_type(self.cache, name, qtype)
  end

  function _M:_get_last_type(name)            -- export as different name!
    return get_last_type(self.cache, name)
  end
end


return _M
