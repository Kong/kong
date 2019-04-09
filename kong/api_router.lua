local lrucache = require "resty.lrucache"
local url      = require "socket.url"
local bit      = require "bit"
local utils    = require "kong.tools.utils"
local reports = require "kong.reports"


local hostname_type = utils.hostname_type
local re_match = ngx.re.match
local re_find  = ngx.re.find
local insert   = table.insert
local upper    = string.upper
local lower    = string.lower
local find     = string.find
local fmt      = string.format
local sub      = string.sub
local tonumber = tonumber
local ipairs   = ipairs
local pairs    = pairs
local type     = type
local band     = bit.band
local bor      = bit.bor
local ERR      = ngx.ERR
local clear_tab
local log


do
  local ngx_log = ngx.log
  log = function(lvl, ...)
    ngx_log(lvl, "[api_router] ", ...)
  end

  local ok
  ok, clear_tab = pcall(require, "table.clear")
  if not ok then
    clear_tab = function(tab)
      for k in pairs(tab) do
        tab[k] = nil
      end
    end
  end
end


--[[
Hypothesis
----------

Item size:        1024 bytes
Max memory limit: 5 MiBs

LRU size must be: (5 * 2^20) / 1024 = 5120
Floored: 5000 items should be a good default
--]]
local MATCH_LRUCACHE_SIZE = 5e3


local MATCH_RULES = {
  HOST            = 0x01,
  URI             = 0x02,
  METHOD          = 0x04,
}

local CATEGORIES = {
  bor(MATCH_RULES.HOST,   MATCH_RULES.URI,     MATCH_RULES.METHOD),
  bor(MATCH_RULES.HOST,   MATCH_RULES.URI),
  bor(MATCH_RULES.HOST,   MATCH_RULES.METHOD),
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


local function has_capturing_groups(subj)
  local s =      find(subj, "[^\\]%(.-[^\\]%)")
  s       = s or find(subj, "^%(.-[^\\]%)")
  s       = s or find(subj, "%(%)")

  return s ~= nil
end


local function marshall_api(api)
  if not (api.headers or api.methods or api.uris) then
    return nil, "could not categorize API"
  end

  local api_t      = {
    api            = api,
    strip_uri      = api.strip_uri,
    preserve_host  = api.preserve_host,
    match_rules    = 0x00,
    hosts          = {},
    uris           = {},
    methods        = {},
    upstream_url_t = {},
  }


  -- headers


  if api.headers then
    if type(api.headers) ~= "table" then
      return nil, "headers field must be a table"
    end

    for header_name in pairs(api.headers) do
      if lower(header_name) ~= "host" then
        return nil, "only 'Host' header is supported in headers field, " ..
                    "found: " .. header_name
      end
    end

    local host_values = api.headers["Host"] or api.headers["host"]
    if type(host_values) ~= "table" then
      return nil, "host field must be a table"
    end

    if #host_values > 0 then
      api_t.match_rules = bor(api_t.match_rules, MATCH_RULES.HOST)

      for _, host_value in ipairs(host_values) do
        if find(host_value, "*", nil, true) then
          -- wildcard host matching
          local wildcard_host_regex = host_value:gsub("%.", "\\.")
                                                :gsub("%*", ".+") .. "$"
          insert(api_t.hosts, {
            wildcard = true,
            value    = host_value,
            regex    = wildcard_host_regex,
          })

        else
          insert(api_t.hosts, {
            value = host_value,
          })
        end

        api_t.hosts[host_value] = host_value
      end
    end
  end


  -- uris


  if api.uris then
    if type(api.uris) ~= "table" then
      return nil, "uris field must be a table"
    end

    if #api.uris > 0 then
      api_t.match_rules = bor(api_t.match_rules, MATCH_RULES.URI)

      for _, uri in ipairs(api.uris) do
        if re_find(uri, [[^[a-zA-Z0-9\.\-_~/%]*$]]) then
          -- plain URI or URI prefix

          local uri_t = {
            is_prefix = true,
            value     = uri,
          }

          api_t.uris[uri] = uri_t
          insert(api_t.uris, uri_t)

        else
          -- regex URI
          local strip_regex  = uri .. [[/?(?<stripped_uri>.*)]]
          local has_captures = has_capturing_groups(uri)

          local uri_t    = {
            is_regex     = true,
            value        = uri,
            regex        = uri,
            has_captures = has_captures,
            strip_regex  = strip_regex,
          }

          api_t.uris[uri] = uri_t
          insert(api_t.uris, uri_t)
        end
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

      for _, method in ipairs(api.methods) do
        api_t.methods[upper(method)] = true
      end
    end
  end


  -- upstream_url parsing


  if api.upstream_url then
    local parsed = url.parse(api.upstream_url)

    api_t.upstream_url_t = {
      scheme             = parsed.scheme,
      host               = parsed.host,
      port               = tonumber(parsed.port),
    }

    api_t.upstream_url_t.type = hostname_type(parsed.host or "")

    if parsed.path then
      api_t.upstream_url_t.path = parsed.path
      api_t.upstream_url_t.file = sub(parsed.path, -1) == "/"
                                  and parsed.path ~= "/"
                                  and sub(parsed.path,  1, -2) or parsed.path
    end

    if not api_t.upstream_url_t.port then
      if parsed.scheme == "https" then
        api_t.upstream_url_t.port = 443

      else
        api_t.upstream_url_t.port = 80
      end
    end
  end


  return api_t
end


local function index_api_t(api_t, plain_indexes, uris_prefixes, uris_regexes,
                           wildcard_hosts)
  for _, host_t in ipairs(api_t.hosts) do
    if host_t.wildcard then
      insert(wildcard_hosts, host_t)

    else
      plain_indexes.hosts[host_t.value] = true
    end
  end

  for _, uri_t in ipairs(api_t.uris) do
    if uri_t.is_prefix then
      plain_indexes.uris[uri_t.value] = true
      insert(uris_prefixes, uri_t)

    else
      insert(uris_regexes, uri_t)
    end
  end

  for method in pairs(api_t.methods) do
    plain_indexes.methods[method] = true
  end
end


local function categorize_api_t(api_t, bit_category, categories)
  local category = categories[bit_category]
  if not category then
    category          = {
      apis_by_hosts   = {},
      apis_by_uris    = {},
      apis_by_methods = {},
      all             = {},
    }

    categories[bit_category] = category
  end

  insert(category.all, api_t)

  for _, host_t in ipairs(api_t.hosts) do
    if not category.apis_by_hosts[host_t.value] then
      category.apis_by_hosts[host_t.value] = {}
    end

    insert(category.apis_by_hosts[host_t.value], api_t)
  end

  for _, uri_t in ipairs(api_t.uris) do
    if not category.apis_by_uris[uri_t.value] then
      category.apis_by_uris[uri_t.value] = {}
    end

    insert(category.apis_by_uris[uri_t.value], api_t)
  end

  for method in pairs(api_t.methods) do
    if not category.apis_by_methods[method] then
      category.apis_by_methods[method] = {}
    end

    insert(category.apis_by_methods[method], api_t)
  end
end


do
  local matchers = {
    [MATCH_RULES.HOST] = function(api_t, ctx)
      local host = api_t.hosts[ctx.hits.host or ctx.req_host]
      if host then
        ctx.matches.host = host

        return true
      end
    end,

    [MATCH_RULES.URI] = function(api_t, ctx)
      do
        local uri_t = api_t.uris[ctx.hits.uri or ctx.req_uri]

        if uri_t then
          if uri_t.is_regex then
            local m, err = re_match(ctx.req_uri, uri_t.strip_regex, "ajo")
            if err then
              log(ERR, "could not evaluate URI prefix/regex: ", err)
              return
            end

            if m then
              if m.stripped_uri then
                ctx.matches.stripped_uri = "/" .. m.stripped_uri
                -- remove the stripped_uri group
                m[#m]          = nil
                m.stripped_uri = nil
              end

              if uri_t.has_captures then
                ctx.matches.uri_captures = m
              end

              ctx.matches.uri = uri_t.value

              return true
            end
          end

          -- plain or prefix match from the index
          if api_t.strip_uri then
            local stripped_uri = sub(ctx.req_uri, #uri_t.value + 1)
            if sub(stripped_uri, 1, 1) ~= "/" then
              stripped_uri = "/" .. stripped_uri
            end

            ctx.matches.stripped_uri = stripped_uri
          end

          ctx.matches.uri = uri_t.value

          return true
        end
      end

      for i = 1, #api_t.uris do
        local uri_t = api_t.uris[i]

        if uri_t.is_regex then
          local m, err = re_match(ctx.req_uri, uri_t.strip_regex, "ajo")
          if err then
            log(ERR, "could not evaluate URI prefix/regex: ", err)
            return
          end

          if m then
            if m.stripped_uri then
              ctx.matches.stripped_uri = "/" .. m.stripped_uri
              -- remove the stripped_uri group
              m[#m]          = nil
              m.stripped_uri = nil
            end

            if uri_t.has_captures then
              ctx.matches.uri_captures = m
            end

            ctx.matches.uri = uri_t.value

            return true
          end

        else
          -- plain or prefix match (not from the index)
          local from, to = find(ctx.req_uri, uri_t.value, nil, true)
          if from == 1 then
            ctx.matches.uri = sub(ctx.req_uri, 1, to)

            if api_t.strip_uri then
              local stripped_uri = sub(ctx.req_uri, to + 1)
              if sub(stripped_uri, 1, 1) ~= "/" then
                stripped_uri = "/" .. stripped_uri
              end

              ctx.matches.stripped_uri = stripped_uri
            end

            ctx.matches.uri = uri_t.value

            return true
          end
        end
      end
    end,

    [MATCH_RULES.METHOD] = function(api_t, ctx)
      local method = api_t.methods[ctx.req_method]
      if method then
        ctx.matches.method = ctx.req_method

        return true
      end
    end
  }


  match_api = function(api_t, ctx)
    -- run cached matcher
    if type(matchers[api_t.match_rules]) == "function" then
      clear_tab(ctx.matches)
      return matchers[api_t.match_rules](api_t, ctx)
    end

    -- build and cache matcher

    local matchers_set = {}

    for _, bit_match_rule in pairs(MATCH_RULES) do
      if band(api_t.match_rules, bit_match_rule) ~= 0 then
        matchers_set[#matchers_set + 1] = matchers[bit_match_rule]
      end
    end

    matchers[api_t.match_rules] = function(api_t, ctx)
      -- clear matches context for this try on this API
      clear_tab(ctx.matches)

      for i = 1, #matchers_set do
        if not matchers_set[i](api_t, ctx) then
          return
        end
      end

      return true
    end

    return matchers[api_t.match_rules](api_t, ctx)
  end
end


do
  local reducers = {
    [MATCH_RULES.HOST] = function(category, ctx)
      return category.apis_by_hosts[ctx.hits.host]
    end,

    [MATCH_RULES.URI] = function(category, ctx)
      return category.apis_by_uris[ctx.hits.uri or ctx.req_uri]
    end,

    [MATCH_RULES.METHOD] = function(category, ctx)
      return category.apis_by_methods[ctx.req_method]
    end,
  }


  reduce = function(category, bit_category, ctx)
    -- run cached reducer
    if type(reducers[bit_category]) == "function" then
      return reducers[bit_category](category, ctx), category.all
    end

    -- build and cache reducer

    local reducers_set = {}

    for _, bit_match_rule in pairs(MATCH_RULES) do
      if band(bit_category, bit_match_rule) ~= 0 then
        reducers_set[#reducers_set + 1] = reducers[bit_match_rule]
      end
    end

    reducers[bit_category] = function(category, ctx)
      local min_len = 0
      local smallest_set

      for i = 1, #reducers_set do
        local candidates = reducers_set[i](category, ctx)
        if candidates ~= nil and (not smallest_set or #candidates < min_len)
        then
          min_len = #candidates
          smallest_set = candidates
        end
      end

      return smallest_set
    end

    return reducers[bit_category](category, ctx), category.all
  end
end


local _M = {}


_M.has_capturing_groups = has_capturing_groups


function _M.new(apis)
  if type(apis) ~= "table" then
    return error("expected arg #1 apis to be a table")
  end


  local self = {}


  local ctx = {
    hits    = {},
    matches = {},
  }


  -- hash table for fast lookup of plain hosts, uris
  -- and methods from incoming requests
  local plain_indexes = {
    hosts             = {},
    uris              = {},
    methods           = {},
  }


  -- when hash lookup in plain_indexes fails, those are arrays
  -- of regexes for `uris` as prefixes and `hosts` as wildcards
  local uris_prefixes  = {} -- will be sorted by length
  local uris_regexes   = {}
  local wildcard_hosts = {}


  -- all APIs grouped by the category they belong to, to reduce
  -- iterations over sets of APIs per request
  local categories = {}


  local cache = lrucache.new(MATCH_LRUCACHE_SIZE)


  -- index APIs


  for i = 1, #apis do
    local api_t, err = marshall_api(apis[i])
    if not api_t then
      return nil, err
    end

    categorize_api_t(api_t, api_t.match_rules, categories)
    index_api_t(api_t, plain_indexes, uris_prefixes, uris_regexes,
                wildcard_hosts)
  end

  table.sort(uris_prefixes, function(a, b)
    return #a > #b
  end)

  table.sort(uris_prefixes, function(uri_t_a, uri_t_b)
    return #uri_t_a.value > #uri_t_b.value
  end)


  local function find_api(req_method, req_uri, req_host, ngx)
    if type(req_method) ~= "string" then
      return error("arg #1 method must be a string")
    end
    if type(req_uri) ~= "string" then
      return error("arg #2 uri must be a string")
    end
    if type(req_host) ~= "string" then
      return error("arg #3 host must be a string")
    end

    -- cache lookup

    local cache_key = fmt("%s:%s:%s", req_method, req_uri, req_host)

    do
      local match_t = cache:get(cache_key)
      if match_t then
        reports.report_cached_entity(match_t)

        return match_t
      end
    end

    -- input sanitization for matchers

    local raw_req_host = req_host

    req_method = upper(req_method)

    if req_host then
      -- strip port number if given because matching ignores ports
      local idx = find(req_host, ":", 2, true)
      if idx then
        req_host = sub(req_host, 1, idx - 1)
      end
    end

    local hits         = ctx.hits
    local req_category = 0x00

    ctx.req_uri    = req_uri
    ctx.req_host   = req_host
    ctx.req_method = req_method

    clear_tab(hits)

    -- router, router, which of these APIs is the fairest?
    --
    -- determine which category this request *might* be targeting

    -- host match

    if plain_indexes.hosts[req_host] then
      req_category = bor(req_category, MATCH_RULES.HOST)

    elseif req_host then
      for i = 1, #wildcard_hosts do
        local from, _, err = re_find(req_host, wildcard_hosts[i].regex, "ajo")
        if err then
          log(ERR, "could not match wildcard host: ", err)
          return
        end

        if from then
          hits.host    = wildcard_hosts[i].value
          req_category = bor(req_category, MATCH_RULES.HOST)
          break
        end
      end
    end

    -- uri match

    if plain_indexes.uris[req_uri] then
      req_category = bor(req_category, MATCH_RULES.URI)

    else
      for i = 1, #uris_prefixes do
        if find(req_uri, uris_prefixes[i].value, nil, true) == 1 then
          hits.uri     = uris_prefixes[i].value
          req_category = bor(req_category, MATCH_RULES.URI)
          break
        end
      end

      for i = 1, #uris_regexes do
        local from, _, err = re_find(req_uri, uris_regexes[i].regex, "ajo")
        if err then
          log(ERR, "could not evaluate URI regex: ", err)
          return
        end

        if from then
          hits.uri     = uris_regexes[i].value
          req_category = bor(req_category, MATCH_RULES.URI)
          break
        end
      end
    end

    -- method match

    if plain_indexes.methods[req_method] then
      req_category = bor(req_category, MATCH_RULES.METHOD)
    end

    --print("highest potential category: ", req_category)

    -- iterate from the highest matching to the lowest category to
    -- find our API

    if req_category ~= 0x00 then
      local category_idx = CATEGORIES_LOOKUP[req_category]
      local matched_api

      while category_idx <= categories_len do
        local bit_category = CATEGORIES[category_idx]
        local category     = categories[bit_category]

        if category then
          local reduced_candidates, category_candidates = reduce(category,
                                                                 bit_category,
                                                                 ctx)
          if reduced_candidates then
            -- check against a reduced set of APIs that is a strong candidate
            -- for this request, instead of iterating over all the APIs of
            -- this category
            for i = 1, #reduced_candidates do
              if match_api(reduced_candidates[i], ctx) then
                matched_api = reduced_candidates[i]
                break
              end
            end
          end

          if not matched_api then
            -- no result from the reduced set, must check for results from the
            -- full list of APIs from that category before checking a lower
            -- category
            for i = 1, #category_candidates do
              if match_api(category_candidates[i], ctx) then
                matched_api = category_candidates[i]
                break
              end
            end
          end

          if matched_api then
            local upstream_host
            local upstream_uri   = req_uri
            local upstream_url_t = matched_api.upstream_url_t
            local matches        = ctx.matches

            -- URI stripping logic

            local uri_root = req_uri == "/"

            if not uri_root and matched_api.strip_uri
               and matches.stripped_uri
            then
              upstream_uri = matches.stripped_uri
            end

            -- uri trailing slash logic

            local upstream_url_path = upstream_url_t.path
            local upstream_url_file = upstream_url_t.file

            if upstream_url_path and upstream_url_path ~= "/" then
              if upstream_uri ~= "/" then
                upstream_uri = upstream_url_file .. upstream_uri

              else
                if upstream_url_path ~= upstream_url_file then
                  if uri_root or sub(req_uri, -1) == "/" then
                    upstream_uri = upstream_url_path

                  else
                    upstream_uri = upstream_url_file
                  end

                else
                  if uri_root or sub(req_uri, -1) ~= "/" then
                    upstream_uri = upstream_url_file

                  else
                    upstream_uri = upstream_url_file .. upstream_uri
                  end
                end
              end
            end

            -- preserve_host header logic

            if matched_api.preserve_host then
              upstream_host = raw_req_host or ngx.var.http_host
            end

            local match_t     = {
              api             = matched_api.api,
              headers         = matched_api.headers,
              upstream_url_t  = upstream_url_t,
              upstream_scheme = upstream_url_t.scheme,
              upstream_uri    = upstream_uri,
              upstream_host   = upstream_host,
              matches         = {
                uri_captures  = matches.uri_captures,
                uri           = matches.uri,
                host          = matches.host,
                method        = matches.method,
              }
            }

            cache:set(cache_key, match_t)

            return match_t
          end
        end

        -- check lower category
        category_idx = category_idx + 1
      end
    end

    -- no match :'(
  end


  self.select = find_api


  function self.exec(ngx)
    local method      = ngx.req.get_method()
    local request_uri = ngx.var.request_uri
    local uri         = request_uri

    do
      local idx = find(uri, "?", 2, true)
      if idx then
        uri = sub(uri, 1, idx - 1)
      end
    end

    local req_host = ngx.var.http_host or ""

    local match_t = find_api(method, uri, req_host, ngx)
    if not match_t then
      return nil
    end

    -- debug HTTP request header logic

    if ngx.var.http_kong_debug then
      ngx.header["Kong-Api-Name"] = match_t.api.name
    end

    return match_t
  end


  return self
end


return _M
