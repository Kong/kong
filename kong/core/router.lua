local lrucache = require "resty.lrucache"
local url = require "socket.url"
local bit = require "bit"


local re_match = ngx.re.match
local re_find = ngx.re.find
local re_sub = ngx.re.sub
local insert = table.insert
local upper = string.upper
local lower = string.lower
local match = string.match
local fmt = string.format
local tonumber = tonumber
local ipairs = ipairs
local pairs = pairs
local type = type
local next = next
local band = bit.band
local bor = bit.bor
local ERR = ngx.ERR
local new_tab
local log


do
  local ok
  ok, new_tab = pcall(require, "table.new")
  if not ok then
    new_tab = function(narr, nrec) return {} end
  end
end


do
  local ngx_log = ngx.log
  log = function(lvl, ...)
    ngx_log(lvl, "[router] ", ...)
  end
end


local MATCH_LRUCACHE_SIZE = 200


local MATCH_RULES = {
  HOST            = 0x01,
  URI             = 0x02,
  METHOD          = 0x04,
}

local CATEGORIES = {
  bor(MATCH_RULES.HOST, MATCH_RULES.URI, MATCH_RULES.METHOD),
  bor(MATCH_RULES.HOST, MATCH_RULES.URI),
  bor(MATCH_RULES.HOST, MATCH_RULES.METHOD),
  bor(MATCH_RULES.METHOD, MATCH_RULES.URI),
  MATCH_RULES.HOST,
  MATCH_RULES.URI,
  MATCH_RULES.METHOD,
}

local categories_len = #CATEGORIES

local CATEGORIES_LOOKUP = {}
for i = 1, categories_len do
  CATEGORIES_LOOKUP[CATEGORIES[i]] = i
end


local match_api
local reduce
local empty_t = {}


local function marshall_api(api)
  local api_t              = {
    api                    = api,
    strip_uri              = api.strip_uri,
    preserve_host          = api.preserve_host,
    match_rules            = 0x00,
    hosts                  = {},
    wildcard_hosts_regexes = {},
    uris                   = {},
    uris_prefixes_regexes  = {},
    methods                = {},
    upstream_scheme        = nil,
    upstream_host          = nil,
    upstream_port          = nil,
  }


  -- headers


  if api.headers then
    if type(api.headers) ~= "table" then
      return nil,  "headers field must be a table"
    end

    for header_name in pairs(api.headers) do
      if lower(header_name) ~= "host" then
        return nil, "only 'Host' header is supported in headers field, "..
                         "found: " .. header_name
      end
    end

    local host_values = api.headers["Host"] or api.headers["host"]
    if type(host_values) ~= "table" then
      return nil, "host field must be a table"
    end

    if #host_values > 0 then
      api_t.match_rules            = bor(api_t.match_rules, MATCH_RULES.HOST)
      api_t.hosts                  = {}
      api_t.wildcard_hosts_regexes = {}

      for _, host_value in ipairs(host_values) do
        if host_value:find("%*") then
          -- wildcard host matching
          local wildcard_host_regex = "^" .. host_value:gsub("%.", "\\.")
                                                       :gsub("%*", ".+") .. "$"
          insert(api_t.wildcard_hosts_regexes, wildcard_host_regex)

        else
          -- plain host matching
          api_t.hosts[host_value] = true
        end
      end
    end
  end


  -- uris


  if api.uris then
    if type(api.uris) ~= "table" then
      return nil, "uris field must be a table"
    end

    if #api.uris > 0 then
      api_t.match_rules         = bor(api_t.match_rules, MATCH_RULES.URI)
      api_t.uris                = new_tab(0, #api.uris)
      api_t.uris_prefix_regexes = new_tab(#api.uris, 0)

      for i, uri in ipairs(api.uris) do
        local escaped_uri = uri:gsub("/", "\\/")
        local strip_regex = "^" .. escaped_uri .. "\\/?(.*)"

        api_t.uris[uri] = {
          strip_regex = strip_regex,
        }

        api_t.uris_prefixes_regexes[i] = {
          regex = "^" .. escaped_uri,
          strip_regex = strip_regex,
        }
      end
    end
  end


  -- methods


  if api.methods then
    if type(api.methods) ~= "table" then
      return nil, "methods field must be a table"
    end

    if #api.methods > 0 then
      api_t.match_rules = bor(api_t.match_rules, MATCH_RULES.METHOD)
      api_t.methods     = new_tab(0, #api.methods)

      for _, method in ipairs(api.methods) do
        api_t.methods[upper(method)] = true
      end
    end
  end


  -- upstream_url parsing


  if api.upstream_url then
    local parsed = url.parse(api.upstream_url)

    api_t.upstream_scheme = parsed.scheme
    api_t.upstream_host = parsed.host
    api_t.upstream_port = tonumber(parsed.port)

    if not api_t.upstream_port then
      if parsed.scheme == "https" then
        api_t.upstream_port = 443

      else
        api_t.upstream_port = 80
      end
    end
  end


  return api_t
end


local function index_api_t(api_t, indexes)
  for host in pairs(api_t.hosts) do
    indexes.plain_hosts[host] = true
  end

  for uri in pairs(api_t.uris) do
    indexes.plain_uris[uri] = true
  end

  for method in pairs(api_t.methods) do
    indexes.methods[method] = true
  end
end


local function categorize_api_t(api_t, categories, uris_prefixes, wildcard_hosts)
  local category = categories[api_t.match_rules]
  if not category then
    category      = {
      plain_hosts = {},
      plain_uris  = {},
      methods     = {},
    }
    categories[api_t.match_rules] = category
  end

  for host in pairs(api_t.hosts) do
    if not category.plain_hosts[host] then
      category.plain_hosts[host] = {}
    end

    insert(category.plain_hosts[host], api_t)
  end

  for uri in pairs(api_t.uris) do
    if not category.plain_uris[uri] then
      category.plain_uris[uri] = {}
    end

    insert(category.plain_uris[uri], api_t)
  end

  for method in pairs(api_t.methods) do
    if not category.methods[method] then
      category.methods[method] = {}
    end

    insert(category.methods[method], api_t)
  end

  --

  for _, wildcard_host_regex in ipairs(api_t.wildcard_hosts_regexes) do
    insert(wildcard_hosts, {
      regex = wildcard_host_regex,
      api_t = api_t,
    })
  end

  for _, uri_prefix_regex in ipairs(api_t.uris_prefixes_regexes) do
    insert(uris_prefixes, {
      regex = uri_prefix_regex.regex,
      api_t = api_t,
    })
  end
end


do

  local matchers = {
    [MATCH_RULES.HOST] = function(api_t, _, _, host)
      -- plain

      if api_t.hosts[host] then
        return true
      end

      -- wildcard

      for i = 1, #api_t.wildcard_hosts_regexes do
        local m, err = re_match(host, api_t.wildcard_hosts_regexes[i], "jo")
        if err then
          log(ERR, "could not match wildcard host: ", err)
          return
        end

        if m then
          return true
        end
      end
    end,

    [MATCH_RULES.URI] = function(api_t, _, uri)
      -- plain

      if api_t.uris[uri] then
        if api_t.strip_uri then
          api_t.strip_uri_regex = api_t.uris[uri].strip_regex
        end

        return true
      end

      -- prefix

      for i = 1, #api_t.uris_prefixes_regexes do
        local from, _, err = re_find(uri, api_t.uris_prefixes_regexes[i].regex, "jo")
        if err then
          log(ERR, "could not search for URI prefix: ", err)
          return
        end

        if from then
          if api_t.strip_uri then
            api_t.strip_uri_regex = api_t.uris_prefixes_regexes[i].strip_regex
          end

          return true
        end
      end
    end,

    [MATCH_RULES.METHOD] = function(api_t, method)
      return api_t.methods[method]
    end
  }


  match_api = function(api_t, method, uri, host)
    -- run cached matcher
    if type(matchers[api_t.match_rules]) == "function" then
      return matchers[api_t.match_rules](api_t, method, uri, host)
    end


    -- build and cache matcher


    local matchers_set = {}

    for _, bit_match_rule in pairs(MATCH_RULES) do
      if band(api_t.match_rules, bit_match_rule) ~= 0 then
        matchers_set[#matchers_set + 1] = matchers[bit_match_rule]
      end
    end

    matchers[api_t.match_rules] = function(api_t, method, uri, host)
      for i = 1, #matchers_set do
        if not matchers_set[i](api_t, method, uri, host) then
          return
        end
      end

      return true
    end

    return matchers[api_t.match_rules](api_t, method, uri, host)
  end
end


do

  local reducers = {
    [MATCH_RULES.HOST] = function(category, _, _, host)
      return category.plain_hosts[host]
    end,

    [MATCH_RULES.URI] = function(category, _, uri)
      return category.plain_uris[uri]
    end,

    [MATCH_RULES.METHOD] = function(category, method)
      return category.methods[method]
    end,
  }

  reduce = function(categories, bit_category, method, uri, host)
    if not categories[bit_category] then
      return
    end

    -- run cached reducer
    if type(reducers[bit_category]) == "function" then
      return reducers[bit_category](categories[bit_category], method, uri, host)
    end


    -- build and cache reducer


    local reducers_set = {}

    for _, bit_match_rule in pairs(MATCH_RULES) do
      if band(bit_category, bit_match_rule) ~= 0 then
        reducers_set[#reducers_set + 1] = reducers[bit_match_rule]
      end
    end

    reducers[bit_category] = function(category, method, uri, host)
      local min_len = 0
      local smallest_set

      for i = 1, #reducers_set do
        local candidates = reducers_set[i](category, method, uri, host)
        if candidates ~= nil and (not smallest_set or #candidates < min_len) then
          min_len = #candidates
          smallest_set = candidates
        end
      end

      return smallest_set
    end

    return reducers[bit_category](categories[bit_category], method, uri, host)
  end
end


local _M = {}


function _M.new(apis)
  if type(apis) ~= "table" then
    return error("expected arg #1 apis to be a table")
  end

  local self = {}

  -- hash table for fast lookup to determine is
  -- an API is registered at given host or URI
  local indexes = {
    plain_hosts = {},
    plain_uris  = {},
    methods     = {},
  }

  local categories = {}

  -- arrays of URIs as prefix and wildcard hosts when
  -- indexes lookups could not determine any candidate
  local uris_prefixes  = {}
  local wildcard_hosts = {}


  local cache = lrucache.new(MATCH_LRUCACHE_SIZE)


  -- index APIs


  for i = 1, #apis do
    local api_t, err = marshall_api(apis[i])
    if not api_t then
      return nil, err
    end

    index_api_t(api_t, indexes)
    categorize_api_t(api_t, categories, uris_prefixes, wildcard_hosts)
  end


  table.sort(wildcard_hosts, function(a, b)
    return a.api_t.match_rules > b.api_t.match_rules
  end)

  table.sort(uris_prefixes, function(a, b)
    if a.api_t.match_rules == b.api_t.match_rules then
      return #a.regex > #b.regex
    end

    return a.api_t.match_rules > b.api_t.match_rules
  end)


  local grab_headers = #wildcard_hosts > 0 or next(indexes.plain_hosts) ~= nil


  local function find_api(method, uri, headers)
    if type(method) ~= "string" then
      return error("arg #1 method must be a string")
    end
    if type(uri) ~= "string" then
      return error("arg #2 uri must be a string")
    end
    if type(headers) ~= "table" then
      return error("arg #3 headers must be a table")
    end


    local host = headers["host"]
    if host then
      host = match(host,"^([^:]+)") -- strip port number if given
    end

    method = upper(method)


    -- cache checking


    local cache_key = fmt("%s:%s:%s", method, uri, host)
    local api_t_from_cache = cache:get(cache_key)
    if api_t_from_cache then
      return api_t_from_cache
    end


    do
      -- plain match checking

      local req_category = 0x00

      if indexes.plain_hosts[host] then
        req_category = bor(req_category, MATCH_RULES.HOST)
      end

      if indexes.plain_uris[uri] then
        req_category = bor(req_category, MATCH_RULES.URI)
      end

      if indexes.methods[method] then
        req_category = bor(req_category, MATCH_RULES.METHOD)
      end

      --print("highest potential category: ", req_category)

      if req_category ~= 0x00 then
        -- we might have a match from our indexes of plain
        -- hosts/URIs/methods
        local category_idx = CATEGORIES_LOOKUP[req_category]

        while category_idx <= categories_len do
          local bit_category = CATEGORIES[category_idx]

          local candidates = reduce(categories, bit_category, method, uri, host)
          if candidates then
            for i = 1, #candidates do
              if match_api(candidates[i], method, uri, host) then
                cache:set(cache_key, candidates[i])
                return candidates[i]
              end
            end
          end

          category_idx = category_idx + 1
        end
      end
    end


    -- URI prefix checking
    -- no API seemed to belong to any of those recorded in our
    -- fast-indexed category lookups, we now want to test for
    -- wildcard hosts and prefix URIs


    for i = 1, #uris_prefixes do
      local from, _, err = re_find(uri, uris_prefixes[i].regex, "jo")
      if err then
        log(ERR, "could not search for URI prefix: ", err)
        return
      end

      -- our URI matches this API's URI as a prefix
      -- let's test all of its other conditions
      if from and match_api(uris_prefixes[i].api_t, method, uri, host) then
        cache:set(cache_key, uris_prefixes[i].api_t)
        return uris_prefixes[i].api_t
      end
    end


    -- wildcard host checking


    for i = 1, #wildcard_hosts do
      local m, err = re_match(host, wildcard_hosts[i].regex, "jo")
      if err then
        log(ERR, "could not match wildcard host: ", err)
        return
      end

      if m and match_api(wildcard_hosts[i].api_t, method, uri, host) then
        cache:set(cache_key, wildcard_hosts[i].api_t)
        return wildcard_hosts[i].api_t
      end
    end


    -- no match :'(
  end


  self.select = find_api


  function self.exec(ngx)
    local method = ngx.req.get_method()
    local uri = ngx.var.uri
    local host_header
    local headers


    --print("grab headers: ", grab_headers)


    if grab_headers then
      headers = ngx.req.get_headers()

    else
      headers = empty_t
    end


    local api_t = find_api(method, uri, headers)
    if not api_t then
      return nil
    end


    if api_t.strip_uri_regex then
      local stripped_uri = re_sub(uri, api_t.strip_uri_regex, "/$1", "jo")
      ngx.req.set_uri(stripped_uri)
    end


    if api_t.preserve_host then
      if not headers then
        headers = ngx.req.get_headers()
      end

      host_header = headers["host"]
    end


    if ngx.var.http_kong_debug then
      ngx.header["Kong-Api-Name"] = api_t.api.name
    end


    return api_t.api, api_t.upstream_scheme, api_t.upstream_host, 
           api_t.upstream_port, host_header
  end


  return self
end


return _M
