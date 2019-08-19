local tablex = require "pl.tablex"
local stringx = require "pl.stringx"
local render_print = require 'pl.pretty'.write
local cjson        = require 'cjson'

-- TODO:
  -- sort
  -- handle nil


local function is_list(table)
  local is_list = true
  for k, v in pairs(table) do
    if type(k) ~= "number" then
      is_list = false
    end
  end

  return is_list
end


-- Apply a function to all values of a table. This returns a table of the results.
-- https://stevedonovan.github.io/Penlight/api/libraries/pl.tablex.html#map
-- https://stevedonovan.github.io/Penlight/api/libraries/pl.tablex.html#imap
local function map(self, map_cb, ...)
  local map = tablex.map
  if is_list(self.ctx) then
    map = tablex.imap
  end

  local ctx = map(map_cb, self.ctx, ...)
  setmetatable(ctx, nil)

  return self
          :set_ctx(ctx)
          :next()
end


-- filter a tables values using a predicate function
local function filter(self, compare_cb, ...)
  local items = self.ctx
  local filtered_items = {}
  local iterator = pairs
  local insert = function(tbl, k, v)
    tbl[k] = v
  end

  if is_list(self.ctx) then
    iterator = ipairs
    insert = function(tbl, k, v)
      table.insert(tbl, v)
    end
  end

  for k, v in iterator(items) do
    local is_valid = compare_cb(k, v, ...)

    if is_valid then
      insert(filtered_items, k, v)
    end
  end

  local ctx = filtered_items
  setmetatable(ctx, nil)

  return self
          :set_ctx(ctx)
          :next()
end


-- total number of elements in this table.
-- https://stevedonovan.github.io/Penlight/api/libraries/pl.tablex.html#size
local function size(self)
  local ctx = tablex.size(self.ctx)

  return self
          :set_ctx(ctx)
          :next()
end


-- return all the values of the table in arbitrary order
-- https://stevedonovan.github.io/Penlight/api/libraries/pl.tablex.html#values
local function values(self)
  local ctx = tablex.values(self.ctx)
  setmetatable(ctx, nil)

  return self
          :set_ctx(ctx)
          :next()
end


-- return all the keys of a table in arbitrary order.
-- https://stevedonovan.github.io/Penlight/api/libraries/pl.tablex.html#keys
local function keys(self)
  local ctx = tablex.keys(self.ctx)
  setmetatable(ctx, nil)

  return self
          :set_ctx(ctx)
          :next()
end


-- extract a range from a table, like ‘string.sub’.
local function sub(self, ...)
  local ctx = tablex.sub(self.ctx, ...)
  setmetatable(ctx, nil)

  return self
          :set_ctx(ctx)
          :next()
end


-- returns value based off of a passed key, or chain of keys
local function val(self, arg)
  local ctx = self.ctx

  if not arg then
    return self
            :set_ctx(ctx)
            :next()
  end

  if ctx[arg] then
    ctx = ctx[arg]

    return self
            :set_ctx(ctx)
            :next()
  end

  local split_arg = stringx.split(arg, '.')
  for i, v in ipairs(split_arg) do
    ctx = ctx[v]
    if ctx == nil then
      return self
              :set_ctx(ctx)
              :next()
    end
  end

  return self
          :set_ctx(ctx)
          :next()
end


-- returns index of list
local function idx(self, arg)
  local ctx = self.ctx[arg]

  return self
          :set_ctx(ctx)
          :next()
end


-- returns json encode
local function json_encode(self)
  local ctx = cjson.encode(self.ctx)

  return self
          :set_ctx(ctx)
          :next()
end


-- returns json encode
local function json_decode(self)
  local ctx = cjson.decode(self.ctx)

  return self
          :set_ctx(ctx)
          :next()
end


-- compares context and arg and returns boolean
local function eq(self, arg)
  local ctx = self.ctx == arg

  return self
          :set_ctx(ctx)
          :next()
end


-- returns string reperesentation of ctx
local function print(self)
  return render_print(self.ctx)
end


-- returns an iterator to a table sorted by its keys
local function pairs(self)
  return tablex.sort(self.ctx)
end


-- return an iterator to a table sorted by its keys
local function sortk(self, ...)
  return tablex.sort(self.ctx, ...)
end


-- return an iterator to a table sorted by its values
local function sortv(self, ...)
  return tablex.sortv(self.ctx, ...)
end


return {
  filter  = filter,
  map     = map,
  values  = values,
  keys    = keys,
  val     = val,
  print   = print,
  size    = size,
  pairs   = pairs,
  idx     = idx,
  sub     = sub,
  sortv   = sortv,
  sortk   = sortk,
  eq      = eq,
  p       = print,
  json_encode = json_encode,
  json_decode = json_decode,
}
