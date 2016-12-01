local url = require "socket.url"
local bit = require "bit"


local re_find = ngx.re.find
local re_sub = ngx.re.sub
local insert = table.insert
local upper = string.upper
local lower = string.lower
local tonumber = tonumber
local ipairs = ipairs
local pairs = pairs
local type = type
local sort = table.sort
local next = next
local band = bit.band
local bor = bit.bor
local max = math.max
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


local index
local match
local reduce


local empty_t = {}
local DEFAULT_NARR = 4
local DEFAULT_NREC = 4


local CATEGORIES = {
  PLAIN_HOST   = 0x01,
  URI          = 0x02,
  PLAIN_METHOD = 0x04,
}
local CATEGORIES_PRIORITIES
local CATEGORIES_PRIORITIES_LOOKUP
local PLAIN_CATEGORIES_LIST


do
  --- list of existing plain categories

  PLAIN_CATEGORIES_LIST = new_tab(4, 0)

  for _, category in pairs(CATEGORIES) do
    PLAIN_CATEGORIES_LIST[#PLAIN_CATEGORIES_LIST + 1] = category
  end

  --- array of existing categories, ordered by priority

  CATEGORIES_PRIORITIES = {
    bor(CATEGORIES.PLAIN_HOST, CATEGORIES.URI, CATEGORIES.PLAIN_METHOD),

    bor(CATEGORIES.PLAIN_HOST, CATEGORIES.URI),
    bor(CATEGORIES.PLAIN_HOST, CATEGORIES.PLAIN_METHOD),
    bor(CATEGORIES.PLAIN_METHOD, CATEGORIES.URI),

    CATEGORIES.PLAIN_HOST,
    CATEGORIES.URI,
    CATEGORIES.PLAIN_METHOD,
  }

  --- lookup table to get category index from its bit value

  CATEGORIES_PRIORITIES_LOOKUP = new_tab(0, #CATEGORIES_PRIORITIES)

  for i, b in ipairs(CATEGORIES_PRIORITIES) do
    CATEGORIES_PRIORITIES_LOOKUP[b] = i
  end
end


do
  --- indexers
  -- @section indexers

  local indexers = {
    [CATEGORIES.PLAIN_HOST] = function(category, indexes, api_t)
      for host_value in pairs(api_t.hosts) do

        indexes.hosts[host_value] = true

        if not category.hosts[host_value] then
          category.hosts[host_value] = new_tab(DEFAULT_NARR, 0)
        end

        insert(category.hosts[host_value], api_t)
      end
    end,
    [CATEGORIES.URI] = function(category, indexes, api_t)
      for uri in pairs(api_t.uris) do
        if not category.uris[uri] then
          category.uris[uri] = new_tab(DEFAULT_NARR, 0)
        end

        insert(category.uris[uri], api_t)
        insert(category.uris_prefix_regex, api_t)
      end
    end,
    [CATEGORIES.PLAIN_METHOD] = function(category, indexes, api_t)
      for method in pairs(api_t.methods) do

        indexes.methods[method] = true

        if not category.methods[method] then
          category.methods[method] = new_tab(DEFAULT_NARR, 0)
        end

        insert(category.methods[method], api_t)
      end
    end,
  }

  index = function(bit_category, indexed_apis, ...)
    if type(indexers[bit_category]) == "function" then
      return indexers[bit_category](indexed_apis[bit_category], ...)
    end

    do
      local indexers_set = new_tab(DEFAULT_NARR, 0)

      for _, category in ipairs(PLAIN_CATEGORIES_LIST) do
        if band(bit_category, category) ~= 0 then
          indexers_set[#indexers_set + 1] = indexers[category]
        end
      end

      indexers[bit_category] = function(...)
        for i = 1, #indexers_set do
          indexers_set[i](...)
        end
      end
    end

    return indexers[bit_category](indexed_apis[bit_category], ...)
  end
end


do
  --- reducers
  -- @section reducers

  local reducers = {
    [CATEGORIES.PLAIN_HOST] = function(category, _, _, headers)
      local host = headers["Host"] or headers["host"]
      return category.hosts[host]
    end,
    [CATEGORIES.URI] = function(category, _, uri)
      local candidates = category.uris[uri]
      if candidates then
        return candidates
      end

      return category.uris_prefix_regex
    end,
    [CATEGORIES.PLAIN_METHOD] = function(category, method)
      return category.methods[method]
    end,
  }

  reduce = function(bit_category, ...)
    if type(reducers[bit_category]) == "function" then
      return reducers[bit_category](...)
    end

    -- no reducer for this category yet, build
    -- and cache a closure for it

    do
      local reducers_set = new_tab(DEFAULT_NARR, 0)

      for _, category in ipairs(PLAIN_CATEGORIES_LIST) do
        if band(bit_category, category) ~= 0 and reducers[category] then
          reducers_set[#reducers_set + 1] = reducers[category]
        end
      end

      reducers[bit_category] = function(...)
        local min_len = 0
        local smallest_set

        for i = 1, #reducers_set do
          local candidates = reducers_set[i](...)
          if candidates ~= nil and (not smallest_set or #candidates < min_len) then
            min_len = #candidates
            smallest_set = candidates
          end
        end

        return smallest_set
      end
    end

    return reducers[bit_category](...)
  end
end


do
  --- matchers
  -- @section matchers

  local matchers = {
    [CATEGORIES.PLAIN_HOST] = function(api_t, _, _, headers)
      local host = headers["Host"] or headers["host"]
      return api_t.hosts[host]
    end,
    [CATEGORIES.URI] = function(api_t, _, uri)
      if api_t.uris[uri] then
        if api_t.strip_uri then
          api_t.strip_uri_regex = api_t.uris_prefix_regex_strip[uri]
        end

        return true
      end

      for i = 1, #api_t.uris_prefix_regex do
        local from, _, err = re_find(uri, api_t.uris_prefix_regex[i], "oj")
        if err then
          log(ERR, "could not search for uri prefix: ", err)
          return
        end

        if from then
          if api_t.strip_uri then
            api_t.strip_uri_regex = api_t.uris_prefix_regex_strip[i]
          end

          return true
        end
      end
    end,
    [CATEGORIES.PLAIN_METHOD] = function(api_t, method)
      return api_t.methods[method]
    end,
  }

  match = function(bit_category, ...)
    if type(matchers[bit_category]) == "function" then
      return matchers[bit_category](...)
    end

    -- no matcher for this category yet, build
    -- and cache a closure for it

    do
      local matchers_set = new_tab(DEFAULT_NARR, 0)

      for _, category in ipairs(PLAIN_CATEGORIES_LIST) do
        if band(bit_category, category) ~= 0 then
          matchers_set[#matchers_set + 1] = matchers[category]
        end
      end

      matchers[bit_category] = function(...)
        for i = 1, #matchers_set do
          if not matchers_set[i](...) then
            return nil
          end
        end

        return true
      end
    end

    return matchers[bit_category](...)
  end
end


--- router
-- @section router


local _M = {}


local function marshall_api(api)
  local bit_category = 0x00
  local api_t = new_tab(0, 8)
  api_t.api = api
  api_t.strip_uri = api.strip_uri

  if api.uris then
    if type(api.uris) ~= "table" then
      return nil, nil, "uris field must be a table"
    end

    if #api.uris > 0 then
      bit_category = bor(bit_category, CATEGORIES.URI)

      api_t.uris = new_tab(0, #api.uris)
      api_t.uris_prefix_regex = new_tab(#api.uris, 0)
      api_t.uris_prefix_regex_strip = new_tab(#api.uris, 0)

      for i, uri in ipairs(api.uris) do
        api_t.uris[uri] = true

        local escaped_uri = uri:gsub("/", "\\/")
        api_t.uris_prefix_regex[i] = "^" .. escaped_uri
        api_t.uris_prefix_regex_strip[i] = "^" .. escaped_uri .. "\\/?(.*)"
        api_t.uris_prefix_regex_strip[uri] = api_t.uris_prefix_regex_strip[i]
      end
    end

  else
    api_t.uris = empty_t
    api_t.uris_prefix_regex = empty_t
  end


  if api.headers then
    if type(api.headers) ~= "table" then
      return nil, nil, "headers field must be a table"
    end

    for header_name in pairs(api.headers) do
      if lower(header_name) ~= "host" then
        return nil, nil, "only 'Host' header is supported in headers field, "..
                         "found: " .. header_name
      end
    end

    -- plain hosts matching

    local host_values = api.headers["Host"] or api.headers["host"]
    if type(host_values) ~= "table" then
      return nil, nil, "host field must be a table"
    end

    if #host_values > 0 then
      bit_category = bor(bit_category, CATEGORIES.PLAIN_HOST)
      api_t.hosts = new_tab(0, #host_values)

      for _, host_value in ipairs(host_values) do
        api_t.hosts[host_value] = true
      end
    end

  else
    api_t.hosts = empty_t
  end


  if api.methods then
    if type(api.methods) ~= "table" then
      return nil, nil, "methods field must be a table"
    end

    -- plain methods matching

    if #api.methods > 0 then
      bit_category = bor(bit_category, CATEGORIES.PLAIN_METHOD)
      api_t.methods = new_tab(0, #api.methods)

      for _, method in ipairs(api.methods) do
        api_t.methods[upper(method)] = true
      end
    end

  else
    api_t.methods = empty_t
  end


  if bit_category == 0x00 then
    return nil, nil, "could not categorize API"
  end


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


  return api_t, bit_category
end


local function new(apis)
  if type(apis) ~= "table" then
    return error("expected arg #1 apis to be a table", 2)
  end


  local self         = new_tab(0, 2)
  local indexes      = new_tab(0, 3)
  local indexed_apis = new_tab(0, #CATEGORIES)
  local grab_headers = false


  do
    -- index APIs
    local n_apis    = #apis
    indexes.hosts   = new_tab(0, n_apis)
    indexes.methods = new_tab(0, n_apis)

    for _, bit_category in ipairs(CATEGORIES_PRIORITIES) do
      indexed_apis[bit_category] = {
        hosts             = new_tab(0, DEFAULT_NREC),
        uris              = new_tab(0, DEFAULT_NREC),
        uris_prefix_regex = new_tab(DEFAULT_NARR, 0),
        methods           = new_tab(0, DEFAULT_NREC),
      }
    end

    for i = 1, n_apis do
      local api_t, bit_category, err = marshall_api(apis[i])
      if err then
        return nil, err
      end

      index(bit_category, indexed_apis, indexes, api_t)
    end

    -- sort APIs by URI length to make "/" the latest, catch-all
    -- route

    for _, index in pairs(indexed_apis) do
      sort(index.uris_prefix_regex, function(api_t_a, api_t_b)
        local longest_uri_a = 0
        local longest_uri_b = 0

        for i = 1, #api_t_a.uris_prefix_regex do
          longest_uri_a = max(longest_uri_a, #api_t_a.uris_prefix_regex[i])
        end

        for i = 1, #api_t_a.uris_prefix_regex do
          longest_uri_b = max(longest_uri_b, #api_t_b.uris_prefix_regex[i])
        end

        return longest_uri_a > longest_uri_b
      end)
    end

    grab_headers = next(indexes.hosts) ~= nil
  end


  local function select_api(method, uri, headers)
    if type(method) ~= "string" then
      return error("arg #1 method must be a string", 2)

    elseif type(uri) ~= "string" then
      return error("arg #2 uri must be a string", 2)

    elseif type(headers) ~= "table" then
      return error("arg #3 headers must be a table", 2)
    end

    method = upper(method)

    -- categorize potential matches for this request
    -- all incoming requests are automatically categorized
    -- as URI by default

    local req_bit_category = CATEGORIES.URI

    do
      local host = headers["Host"] or headers["host"]
      if host and indexes.hosts[host] then
        req_bit_category = bor(req_bit_category, CATEGORIES.PLAIN_HOST)
      end

      if indexes.methods[method] then
        req_bit_category = bor(req_bit_category, CATEGORIES.PLAIN_METHOD)
      end

      --print("highest potential category: ", req_bit_category)
    end

    -- retrieve highest potential category

    local cat_idx = CATEGORIES_PRIORITIES_LOOKUP[req_bit_category]

    -- iterate over categories from the highest one

    while cat_idx <= #CATEGORIES_PRIORITIES do
      local bit_category = CATEGORIES_PRIORITIES[cat_idx]
      local category = indexed_apis[bit_category]

      local reduced = reduce(bit_category, category, method, uri, headers)
      if reduced then
        for i = 1, #reduced do
          if match(bit_category, reduced[i], method, uri, headers) then
            return reduced[i]
          end
        end
      end

      cat_idx = cat_idx + 1
    end
  end


  self.select = select_api


  function self.exec(ngx)
    local method = ngx.req.get_method()
    local uri = ngx.var.uri
    local headers

    --print("grab headers: ", grab_headers)

    if grab_headers then
      headers = ngx.req.get_headers()

    else
      headers = empty_t
    end


    local api_t = select_api(method, uri, headers)
    if not api_t then
      return nil
    end


    if api_t.strip_uri_regex then
      local stripped_uri = re_sub(uri, api_t.strip_uri_regex, "/$1", "oj")
      ngx.req.set_uri(stripped_uri)
    end


    if ngx.var.http_kong_debug then
      ngx.header["Kong-Api-Name"] = api_t.api.name
    end


    return api_t.api, api_t.upstream_scheme, api_t.upstream_host, api_t.upstream_port
  end


  return self
end


_M.new = new


return _M
