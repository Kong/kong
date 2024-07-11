local cjson = require("cjson.safe")
local utils = require("kong.resty.dns_client.utils")
local mlcache = require("kong.resty.mlcache")
local resolver = require("resty.dns.resolver")

local parse_hosts   = utils.parse_hosts
local ipv6_bracket  = utils.ipv6_bracket
local search_names  = utils.search_names
local get_round_robin_answers          = utils.get_round_robin_answers
local get_weighted_round_robin_answers = utils.get_weighted_round_robin_answers

local now       = ngx.now
local log       = ngx.log
local ERR       = ngx.ERR
local WARN      = ngx.WARN
local ALERT     = ngx.ALERT
local timer_at  = ngx.timer.at

local type          = type
local pairs         = pairs
local ipairs        = ipairs
local math_min      = math.min
local table_insert  = table.insert

local req_dyn_hook_run_hooks = require("kong.dynamic_hook").run_hooks

-- Constants and default values
local DEFAULT_ERROR_TTL = 1     -- unit: second
local DEFAULT_STALE_TTL = 4
local DEFAULT_EMPTY_TTL = 30

local DEFAULT_ORDER = { "LAST", "SRV", "A", "AAAA", "CNAME" }

local TYPE_SRV      = resolver.TYPE_SRV
local TYPE_A        = resolver.TYPE_A
local TYPE_AAAA     = resolver.TYPE_AAAA
local TYPE_CNAME    = resolver.TYPE_CNAME
local TYPE_LAST     = -1

local valid_type_names = {
  SRV     = TYPE_SRV,
  A       = TYPE_A,
  AAAA    = TYPE_AAAA,
  CNAME   = TYPE_CNAME,
  LAST    = TYPE_LAST,
}

local typstrs = {
  [TYPE_SRV]      = "SRV",
  [TYPE_A]        = "A",
  [TYPE_AAAA]     = "AAAA",
  [TYPE_CNAME]    = "CNAME",
}

local HIT_L3 = 3 -- L1 lru, L2 shm, L3 callback, L4 stale

local hitstrs = {
  [1] = "hit_lru",
  [2] = "hit_shm",
  [3] = "hit_cb",
  [4] = "hit_stale",
}

-- server replied error from the DNS protocol
local NAME_ERROR_CODE    = 3 -- response code 3 as "Name Error" or "NXDOMAIN"
local NAME_ERROR_ANSWERS = { errcode = NAME_ERROR_CODE, errstr = "name error" }
-- client specific error
local CACHE_ONLY_EC      = 100
local CACHE_ONLY_ESTR    = "cache only lookup failed"
local CACHE_ONLY_ANSWERS = { errcode = CACHE_ONLY_EC, errstr = CACHE_ONLY_ESTR }
local EMPTY_RECORD_EC    = 101
local EMPTY_RECORD_ESTR  = "empty record received"


-- APIs
local _M = {}
local mt = { __index = _M }

-- copy TYPE_*
for k,v in pairs(resolver) do
  if type(k) == "string" and k:sub(1,5) == "TYPE_" then
    _M[k] = v
  end
end
_M.TYPE_LAST = -1


local tries_mt = { __tostring = cjson.encode }


local function stats_init(stats, name)
  if not stats[name] then
    stats[name] = {}
  end
end


local function stats_count(stats, name, key)
  stats[name][key] = (stats[name][key] or 0) + 1
end


-- lookup or set TYPE_LAST (the DNS record type from the last successful query)
local function insert_last_type(cache, name, qtype)
  local key = "last:" .. name
  if typstrs[qtype] and cache:get(key) ~= qtype then
    cache:set(key, { ttl = 0 }, qtype)
  end
end


local function get_last_type(cache, name)
  return cache:get("last:" .. name)
end


-- insert hosts into cache
local function init_hosts(cache, path, preferred_ip_type)
  local hosts, err = parse_hosts(path)
  if not hosts then
    log(WARN, "Invalid hosts file: ", err)
    hosts = {}
  end

  if not hosts.localhost then
    hosts.localhost = {
      ipv4 = "127.0.0.1",
      ipv6 = "[::1]",
    }
  end

  local function insert_answer(name, qtype, address)
    if not address then
      return
    end

    local ttl = 10 * 365 * 24 * 60 * 60 -- 10 years ttl for hosts entries

    local key = name .. ":" .. qtype
    local answers = {
      ttl = ttl,
      expire = now() + ttl,
      {
        name = name,
        type = qtype,
        address = address,
        class = 1,
        ttl = ttl,
      },
    }
    -- insert via the `:get` callback to prevent inter-process communication
    cache:get(key, nil, function()
      return answers, nil, ttl
    end)
  end

  for name, address in pairs(hosts) do
    name = name:lower()
    if address.ipv4 then
      insert_answer(name, TYPE_A, address.ipv4)
      insert_last_type(cache, name, TYPE_A)
    end
    if address.ipv6 then
      insert_answer(name, TYPE_AAAA, address.ipv6)
      if not address.ipv4 or preferred_ip_type == TYPE_AAAA then
        insert_last_type(cache, name, TYPE_AAAA)
      end
    end
  end

  return hosts
end


-- distinguish the worker_events sources registered by different new() instances
local ipc_counter = 0

function _M.new(opts)
  if not opts then
    return nil, "no options table specified"
  end

  -- parse resolv.conf
  local resolv, err = utils.parse_resolv_conf(opts.resolv_conf, opts.enable_ipv6)
  if not resolv then
    log(WARN, "Invalid resolv.conf: ", err)
    resolv = { options = {} }
  end

  -- init the resolver options for lua-resty-dns
  local nameservers = (opts.nameservers and #opts.nameservers > 0) and
                      opts.nameservers or resolv.nameservers
  if not nameservers or #nameservers == 0 then
    log(WARN, "Invalid configuration, no nameservers specified")
  end

  local r_opts = {
    retrans     = opts.retrans or resolv.options.attempts or 5,
    timeout     = opts.timeout or resolv.options.timeout or 2000, -- ms
    no_random   = opts.no_random or not resolv.options.rotate,
    nameservers = nameservers,
  }

  -- init the mlcache
  local lock_timeout = r_opts.timeout / 1000 * r_opts.retrans + 1 -- s

  local resty_lock_opts = {
    timeout = lock_timeout,
    exptimeout = lock_timeout + 1,
  }

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
    shm_miss        = "kong_dns_cache_miss",
    resty_lock_opts = resty_lock_opts,
  })

  if not cache then
    return nil, "could not create mlcache: " .. err
  end

  if opts.cache_purge then
    cache:purge(true)
  end

  -- parse order
  local search_types = {}
  local order = opts.order or DEFAULT_ORDER
  local preferred_ip_type
  for _, typstr in ipairs(order) do
    local qtype = valid_type_names[typstr:upper()]
    if not qtype then
      return nil, "Invalid dns record type in order array: " .. typstr
    end

    table_insert(search_types, qtype)

    if (qtype == TYPE_A or qtype == TYPE_AAAA) and not preferred_ip_type then
      preferred_ip_type = qtype
    end
  end
  preferred_ip_type = preferred_ip_type or TYPE_A

  if #search_types == 0 then
    return nil, "Invalid order array: empty record types"
  end

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
  }, mt)
end


local function process_answers(self, qname, qtype, answers)
  local errcode = answers.errcode
  if errcode then
    answers.ttl = errcode == NAME_ERROR_CODE and self.empty_ttl or self.error_ttl
    -- compatible with balancer, which needs this field
    answers.expire = now() + answers.ttl
    return answers
  end

  local processed_answers = {}
  local cname_answer

  local ttl = self.valid_ttl or 0xffffffff

  for _, answer in ipairs(answers) do
    answer.name = answer.name:lower()

    if answer.type == TYPE_CNAME then
      cname_answer = answer   -- use the last one as the real cname

    elseif answer.type == qtype then
      -- compatible with balancer, see https://github.com/Kong/kong/pull/3088
      if answer.type == TYPE_AAAA then
        answer.address = ipv6_bracket(answer.address)
      elseif answer.type == TYPE_SRV then
        answer.target = ipv6_bracket(answer.target)
      end

      table_insert(processed_answers, answer)
    end

    if self.valid_ttl then
      answer.ttl = self.valid_ttl
    else
      ttl = math_min(ttl, answer.ttl)
    end
  end

  if #processed_answers == 0 then
    if not cname_answer then
      return {
        errcode = EMPTY_RECORD_EC,
        errstr  = EMPTY_RECORD_ESTR,
        ttl     = self.empty_ttl,
        -- expire = now() + self.empty_ttl,
      }
    end

    table_insert(processed_answers, cname_answer)
  end

  processed_answers.expire = now() + ttl
  processed_answers.ttl = ttl

  return processed_answers
end


local function resolve_query(self, name, qtype, tries)
  local key = name .. ":" .. qtype
  stats_count(self.stats, key, "query")

  local r, err = resolver:new(self.r_opts)
  if not r then
    return nil, "failed to instantiate the resolver: " .. err
  end

  local options = { additional_section = true, qtype = qtype }
  local answers, err = r:query(name, options)
  if r.destroy then
    r:destroy()
  end

  if not answers then
    stats_count(self.stats, key, "query_fail")
    return nil, "DNS server error: " .. (err or "unknown")
  end

  answers = process_answers(self, name, qtype, answers)

  stats_count(self.stats, key, answers.errstr and "query_err:" .. answers.errstr
                                               or "query_succ")

  return answers, nil, answers.ttl
end


local function start_stale_update_task(self, key, name, qtype)
  stats_count(self.stats, key, "stale")

  timer_at(0, function (premature)
    if premature then
      return
    end

    local answers = resolve_query(self, name, qtype, {})
    if answers and (not answers.errcode or answers.errcode == NAME_ERROR_CODE) then
      self.cache:set(key, { ttl = answers.ttl },
                     answers.errcode ~= NAME_ERROR_CODE and answers or nil)
      insert_last_type(self.cache, name, qtype)
    end
  end)
end


local function resolve_name_type_callback(self, name, qtype, opts, tries)
  local key = name .. ":" .. qtype

  -- `:peek(stale=true)` verifies if the expired key remains in L2 shm, then
  -- initiates an asynchronous background updating task to refresh it.
  local ttl, _, answers = self.cache:peek(key, true)
  if answers and ttl and not answers.expired then
    ttl = ttl + self.stale_ttl
    if ttl > 0 then
      start_stale_update_task(self, key, name, qtype)
      answers.expire = now() + ttl
      answers.expired = true
      answers.ttl = ttl
      return answers, nil, ttl
    end
  end

  if opts.cache_only then
    return CACHE_ONLY_ANSWERS, nil, -1
  end

  local answers, err, ttl = resolve_query(self, name, qtype, tries)

  if answers and answers.errcode == NAME_ERROR_CODE then
    return nil  -- empty record for shm_miss cache
  end

  return answers, err, ttl
end


local function detect_recursion(opts, key)
  local rn = opts.resolved_names
  if not rn then
    rn = {}
    opts.resolved_names = rn
  end
  local detected = rn[key]
  rn[key] = true
  return detected
end


local function resolve_name_type(self, name, qtype, opts, tries)
  local key = name .. ":" .. qtype

  stats_init(self.stats, key)

  if detect_recursion(opts, key) then
    stats_count(self.stats, key, "fail_recur")
    return nil, "recursion detected for name: " .. key
  end

  local answers, err, hit_level = self.cache:get(key, nil,
                                                 resolve_name_type_callback,
                                                 self, name, qtype, opts, tries)
  -- check for runtime errors in the callback
  if err and err:sub(1, 8) == "callback" then
    log(ALERT, err)
  end

  -- restore the nil value in mlcache shm_miss to "name error" answers
  if not answers and not err then
    answers = NAME_ERROR_ANSWERS
  end

  local ctx = ngx.ctx
  if ctx and ctx.has_timing then
    req_dyn_hook_run_hooks(ctx, "timing", "dns:cache_lookup",
                           (hit_level and hit_level < HIT_L3))
  end

  -- hit L1 lru or L2 shm
  if hit_level and hit_level < HIT_L3 then
    stats_count(self.stats, key, hitstrs[hit_level])
  end

  if err or answers.errcode then
    if not err then
      local src = answers.errcode < CACHE_ONLY_EC and "server" or "client"
      err = ("dns %s error: %s %s"):format(src, answers.errcode, answers.errstr)
    end
    table_insert(tries, { name .. ":" .. typstrs[qtype], err })
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
    return {{ name = name, class = 1, type = TYPE_A, address = name }}
  end

  if name:match(":") then                     -- IPv6
    return {{ name = name, class = 1, type = TYPE_AAAA, address = ipv6_bracket(name) }}
  end

  return nil
end


local function resolve_names_and_types(self, name, opts, tries)
  local answers = check_and_get_ip_answers(name)
  if answers then
    answers.ttl = 10 * 365 * 24 * 60 * 60
    answers.expire = now() + answers.ttl
    return answers, nil, tries
  end

  -- TODO: For better performance, it may be necessary to rewrite it as an
  --       iterative function.
  local types = get_search_types(self, name, opts.qtype)
  local names = search_names(name, self.resolv, self.hosts)

  local err
  for _, qtype in ipairs(types) do
    for _, qname in ipairs(names) do
      answers, err = resolve_name_type(self, qname, qtype, opts, tries)

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


local function resolve_all(self, name, opts, tries)
  -- key like "short:example.com:all" or "short:example.com:5"
  local key = "short:" .. name .. ":" .. (opts.qtype or "all")

  stats_init(self.stats, name)
  stats_count(self.stats, name, "runs")

  if detect_recursion(opts, key) then
    stats_count(self.stats, name, "fail_recur")
    return nil, "recursion detected for name: " .. name
  end

  -- quickly lookup with the key "short:<name>:all" or "short:<name>:<qtype>"
  local answers, err, hit_level = self.cache:get(key)
  if not answers or answers.expired then
    stats_count(self.stats, name, "miss")

    answers, err, tries = resolve_names_and_types(self, name, opts, tries)
    if not opts.cache_only and answers then
      self.cache:set(key, { ttl = answers.ttl }, answers)
    end

  else
    local ctx = ngx.ctx
    if ctx and ctx.has_timing then
      req_dyn_hook_run_hooks(ctx, "timing", "dns:cache_lookup",
                             (hit_level and hit_level < HIT_L3))
    end

    stats_count(self.stats, name, hitstrs[hit_level])
  end

  -- dereference CNAME
  if opts.qtype ~= TYPE_CNAME and answers and answers[1].type == TYPE_CNAME then
    stats_count(self.stats, name, "cname")
    return resolve_all(self, answers[1].cname, opts, tries)
  end

  stats_count(self.stats, name, answers and "succ" or "fail")

  return answers, err, tries
end


-- resolve all `name`s and `type`s combinations and return first usable answers
--   `name`s: produced by resolv.conf options: `search`, `ndots` and `domain`
--   `type`s: SRV, A, AAAA, CNAME
--
-- @opts:
--   `return_random`: default `false`, return only one random IP address
--   `cache_only`: default `false`, retrieve data only from the internal cache
--   `qtype`: specified query type instead of its own search types
function _M:resolve(name, opts, tries)
  name = name:lower()
  opts = opts or {}
  tries = setmetatable(tries or {}, tries_mt)

  local answers, err, tries = resolve_all(self, name, opts, tries)
  if not answers or not opts.return_random then
    return answers, err, tries
  end

  -- option: return_random
  if answers[1].type == TYPE_SRV then
    local answer = get_weighted_round_robin_answers(answers)
    opts.port = answer.port ~= 0 and answer.port or opts.port
    return self:resolve(answer.target, opts, tries)
  end

  return get_round_robin_answers(answers).address, opts.port, tries
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
  local opts = { cache_only = cache_only }
  return dns_client:_resolve(name, opts, tries)
end


function _M.toip(name, port, cache_only, tries)
  local opts = { cache_only = cache_only, return_random = true , port = port }
  return dns_client:_resolve(name, opts, tries)
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
  function _M:insert_last_type(name, qtype)
    insert_last_type(self.cache, name, qtype)
  end
  function _M:get_last_type(name)
    return get_last_type(self.cache, name)
  end
  _M._init = _M.init
  function _M.init(opts)
    opts = opts or {}
    opts.cache_purge = true
    return _M._init(opts)
  end
end


return _M
