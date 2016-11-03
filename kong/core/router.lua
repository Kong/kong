local bit = require "bit"


local insert = table.insert
local upper = string.upper
local lower = string.lower
local ipairs = ipairs
local pairs = pairs
local type = type
local band = bit.band
local bor = bit.bor
local new_tab


do
  local ok
  ok, new_tab = pcall(require, "table.new")
  if not ok then
    new_tab = function(narr, nrec) return {} end
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
  PLAIN_URI    = 0x02,
  PLAIN_METHOD = 0x04,
}
local CATEGORIES_PRIORITIES
local CATEGORIES_PRIORITIES_LOOKUP
local PLAIN_CATEGORIES_LIST


do
  --- list of existing plain categories

  PLAIN_CATEGORIES_LIST = new_tab(3, 0)

  for _, category in pairs(CATEGORIES) do
    PLAIN_CATEGORIES_LIST[#PLAIN_CATEGORIES_LIST + 1] = category
  end

  --- array of existing categories, ordered by priority

  CATEGORIES_PRIORITIES = {
    bor(CATEGORIES.PLAIN_HOST, CATEGORIES.PLAIN_URI, CATEGORIES.PLAIN_METHOD)
    ;
    bor(CATEGORIES.PLAIN_HOST, CATEGORIES.PLAIN_URI),
    bor(CATEGORIES.PLAIN_HOST, CATEGORIES.PLAIN_METHOD),
    bor(CATEGORIES.PLAIN_URI, CATEGORIES.PLAIN_METHOD)
    ;
    CATEGORIES.PLAIN_HOST,
    CATEGORIES.PLAIN_URI,
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
    [CATEGORIES.PLAIN_HOST] = function(indexed_apis_category, indexes, api_t)
      for host_value in pairs(api_t.hosts) do

        indexes.hosts[host_value] = true

        if not indexed_apis_category.hosts[host_value] then
          indexed_apis_category.hosts[host_value] = new_tab(DEFAULT_NARR, 0)
        end

        insert(indexed_apis_category.hosts[host_value], api_t)
      end
    end,
    [CATEGORIES.PLAIN_URI] = function(indexed_apis_category, indexes, api_t)
      for uri in pairs(api_t.uris) do

        indexes.uris[uri] = true

        if not indexed_apis_category.uris[uri] then
          indexed_apis_category.uris[uri] = new_tab(DEFAULT_NARR, 0)
        end

        insert(indexed_apis_category.uris[uri], api_t)
      end
    end,
    [CATEGORIES.PLAIN_METHOD] = function(indexed_apis_category, indexes, api_t)
      for method in pairs(api_t.methods) do

        indexes.methods[method] = true

        if not indexed_apis_category.methods[method] then
          indexed_apis_category.methods[method] = new_tab(DEFAULT_NARR, 0)
        end

        insert(indexed_apis_category.methods[method], api_t)
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
    [CATEGORIES.PLAIN_URI] = function(category, _, uri)
      return category.uris[uri]
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
        if band(bit_category, category) ~= 0 then
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
    [CATEGORIES.PLAIN_URI] = function(api_t, _, uri)
      return api_t.uris[uri]
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
  local api_t = new_tab(0, 4)
  api_t.api = api

  if api.uris then
    if type(api.uris) ~= "table" then
      return nil, nil, "uris field must be a table"
    end

    -- plain uris matching

    bit_category = bor(bit_category, CATEGORIES.PLAIN_URI)
    api_t.uris = new_tab(0, #api.uris)

    for _, uri in ipairs(api.uris) do
      api_t.uris[uri] = true
    end

  else
    api_t.uris = empty_t
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

    bit_category = bor(bit_category, CATEGORIES.PLAIN_HOST)
    api_t.hosts = new_tab(0, #host_values)

    for _, host_value in ipairs(host_values) do
      api_t.hosts[host_value] = true
    end

  else
    api_t.hosts = empty_t
  end


  if api.methods then
    if type(api.methods) ~= "table" then
      return nil, nil, "methods field must be a table"
    end

    -- plain methods matching

    bit_category = bor(bit_category, CATEGORIES.PLAIN_METHOD)
    api_t.methods = new_tab(0, #api.methods)

    for _, method in ipairs(api.methods) do
      api_t.methods[upper(method)] = true
    end

  else
    api_t.methods = empty_t
  end


  if bit_category == 0x00 then
    return nil, nil, "could not categorize API"
  end


  return api_t, bit_category
end


local function new(apis)
  if type(apis) ~= "table" then
    return error("expected arg #1 apis to be a table", 2)
  end


  local self         = new_tab(0, 1)
  local indexes      = new_tab(0, 3)
  local indexed_apis = new_tab(0, #CATEGORIES)


  do
    -- index APIs
    local n_apis    = #apis
    indexes.hosts   = new_tab(0, n_apis)
    indexes.uris    = new_tab(0, n_apis)
    indexes.methods = new_tab(0, n_apis)

    for _, bit_category in ipairs(CATEGORIES_PRIORITIES) do
      indexed_apis[bit_category] = {
        hosts   = new_tab(0, DEFAULT_NREC),
        uris    = new_tab(0, DEFAULT_NREC),
        methods = new_tab(0, DEFAULT_NREC),
      }
    end

    for i = 1, n_apis do
      local api_t, bit_category, err = marshall_api(apis[i])
      if err then
        return nil, err
      end

      index(bit_category, indexed_apis, indexes, api_t)
    end
  end


  function self.exec(method, uri, headers)
    if type(method) ~= "string" then
      return error("arg #1 method must be a string", 2)

    elseif type(uri) ~= "string" then
      return error("arg #2 uri must be a string", 2)

    elseif type(headers) ~= "table" then
      return error("arg #3 headers must be a table", 2)
    end

    method = upper(method)

    -- categorize potential matches for this request

    local req_bit_category = 0x00

    do
      local host = headers["Host"] or headers["host"]
      if host and indexes.hosts[host] then
        req_bit_category = bor(req_bit_category, CATEGORIES.PLAIN_HOST)
      end

      if indexes.uris[uri] then
        req_bit_category = bor(req_bit_category, CATEGORIES.PLAIN_URI)
      end

      if indexes.methods[method] then
        req_bit_category = bor(req_bit_category, CATEGORIES.PLAIN_METHOD)
      end

      --print("highest potential category: ", req_bit_category)
    end

    if req_bit_category == 0x00 then
      -- no match in any category
      return
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
            return reduced[i].api
          end
        end
      end

      cat_idx = cat_idx + 1
    end
  end


  return self
end


_M.new = new


return _M
