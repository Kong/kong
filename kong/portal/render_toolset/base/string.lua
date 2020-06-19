local stringx = require "pl.stringx"
-- local render_print = require 'pl.pretty'.write


local stringx_split = stringx.split

local string_upper = string.upper
local string_lower = string.lower
local string_gsub  = string.gsub
local string_reverse = string.reverse


-- Changes lowercase characters in a string to uppercase.
-- https://docs.coronalabs.com/api/library/string/upper.html
local function upper(self)
  local ctx = string_upper(self.ctx)

  return self
          :set_ctx(ctx)
          :next()
end

-- Change uppercase characters in a string to lowercase.
-- https://docs.coronalabs.com/api/library/string/lower.html
local function lower(self)
  local ctx = string_lower(self.ctx)

  return self
          :set_ctx(ctx)
          :next()
end


-- Replaces all occurrences of a pattern in a string.
-- https://docs.coronalabs.com/api/library/string/gsub.html
local function gsub(self, ...)
  local ctx = string_gsub(self.ctx, ...)

  return self
          :set_ctx(ctx)
          :next()
end


-- Returns the length of a string (number of characters).
local function len(self)
  local ctx = #self.ctx

  return self
          :set_ctx(ctx)
          :next()
end


-- Reverses a string.
-- https://docs.coronalabs.com/api/library/string/reverse.html
local function reverse(self)
  local ctx = string_reverse(self.ctx)

  return self
          :set_ctx(ctx)
          :next()
end


-- split a string into a list of strings using a delimiter
-- https://stevedonovan.github.io/Penlight/api/libraries/pl.stringx.html#split
local function split(self, string, int)
  local ctx = stringx_split(self.ctx, string, int)

  return self
          :set_ctx(ctx)
          :next()
end


-- returns string reperesentation of ctx
local function print(self)
  return self.ctx
end


return {
  upper   = upper,
  lower   = lower,
  gsub    = gsub,
  len     = len,
  reverse = reverse,
  split   = split,
  print   = print,
  p       = print,
}
