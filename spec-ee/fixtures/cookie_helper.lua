-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local date = require "date"

-- A cookie helper class
local Cookie = {}
Cookie.__index = Cookie

-- Create a new cookie
function Cookie:new(name, value, path)
  local cookie = {
    name = name,
    value = value or "",
    path = path or "/",
    expires = nil
  }
  setmetatable(cookie, self)
  return cookie
end

-- Cookie is able to be converted to a header string
function Cookie:to_header()
  local cookie_str = self.name .. "=" .. self.value
  if self.path then
    cookie_str = cookie_str .. "; path=" .. self.path
  end
  return cookie_str
end

-- CookieManager is able to manage multiple cookies
local CookieManager = {}
CookieManager.__index = CookieManager

-- Create a new cookie manager
function CookieManager:new()
  local cookie_mgr = {
    cookies = {}
  }
  setmetatable(cookie_mgr, self)
  return cookie_mgr
end

-- Add a cookie to the manager
function CookieManager:add(name, value, path)
  local cookie = Cookie:new(name, value, path)
  table.insert(self.cookies, cookie)
end

local function trim(s)
  return (s:gsub("^%s*(.-)%s*$", "%1"))
end

-- Parse Set-Cookie header and add to the manager
function CookieManager:from_set_cookie(cookie_string)
  local parts = cookie_string:gmatch("([^;]+)")
  local main_part = parts()
  local name, value = main_part:match("([^=]+)=([^=]+)")

  -- find the cookie in self.cookies if exists
  local cookie
  for _, c in ipairs(self.cookies) do
    if c.name == name then
      cookie = c
      break
    end
  end

  -- or insert a new one to self.cookies
  if not cookie then
    cookie = Cookie:new(name, value)
    table.insert(self.cookies, cookie)
  end

  for other_part in parts do
    local opt_iter = other_part:gmatch("([^=]+)")
    local opt_name = opt_iter()
    opt_name = trim(opt_name)

    if opt_name:lower() == "path" then
      cookie.path = trim(opt_iter())
    elseif opt_name:lower() == "expires" then
      local expires = trim(opt_iter())
      local expires_date = date(expires)
      if expires_date < date() then
        -- remove the cookie if it's expired
        for i, c in ipairs(self.cookies) do
          if c.name == name then
            table.remove(self.cookies, i)
            break
          end
        end
        -- and break the parse loop
        break
      else
        cookie.expires = date(expires)
      end
    end
  end
end

function CookieManager:parse_set_cookie_headers(headers)
  if type(headers) == "table" then
    for _, cookie_string in ipairs(headers) do
      self:from_set_cookie(cookie_string)
    end
  else
    self:from_set_cookie(headers) -- is cookie_string
  end
end

-- Get a cookie by name
function CookieManager:get(name)
  for _, cookie in ipairs(self.cookies) do
    if cookie.name == name then
      return cookie
    end
  end
end

-- CookieManager is able to be converted to a header string
function CookieManager:to_header(path)
  local cookie_str = ""
  for _, cookie in ipairs(self.cookies) do
    if path == nil or cookie.path == "/" or cookie.path:find("^" .. path) ~= nil then
      cookie_str = cookie_str .. cookie:to_header() .. "; "
    end
  end

  -- remove trailing "; "
  return cookie_str:sub(1, -3)
end

return {
  Cookie = Cookie,
  CookieManager = CookieManager
}
