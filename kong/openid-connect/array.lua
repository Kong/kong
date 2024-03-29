-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local regmatch = ngx.re.gmatch
local ipairs   = ipairs
local type     = type


local array = {}


function array.has(needle, arr)
  if needle == nil or type(arr) ~= "table" then
    return false
  end

  local ndl, c = array.new(needle)
  if c == 0 then
    return false
  end

  local i = 0

  for _, n in ipairs(ndl) do
    for _, v in ipairs(arr) do
      local found
      if n == v then
        found = true

      else
        local values = array.new(v)
        for _, w in ipairs(values) do
          if n == w then
            found = true
          end
        end
      end

      if found then
        i = i + 1
        break
      end
    end
  end

  return i == c
end


function array.remove(needle, arr)
  if needle == nil or type(arr) ~= "table" then
    return
  end

  local ndl    = array.new(needle)
  local res, i = {}, 0

  for _, v in ipairs(arr) do
    local f
    for _, n in ipairs(ndl) do
      if n == v then
        f = true
        break
      end
    end

    if not f then
      i = i + 1
      res[i] = v
    end
  end

  return res, i
end


function array.new(init, defaults)
  local res, i = {}, 0

  if defaults then
    local def = array.new(defaults)

    for _, v in ipairs(def) do
      if not array.has(v, res) then
        i = i + 1
        res[i] = v
      end
    end
  end

  if type(init) == "string" then
    local values, err = regmatch(init, [[([^\s]+)]], "jo")
    if not values then
      return nil, err
    end

    for t in values do
      i = i + 1
      res[i] = t[1]
    end

  elseif type(init) == "table" then
    for _, v in ipairs(init) do
      i = i + 1
      res[i] = v
    end

  elseif init ~= nil then
    i = i + 1
    res[i] = init
  end

  return res, i
end


return array
