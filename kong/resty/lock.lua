-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

-- Bundled from https://github.com/openresty/lua-resty-lock with hotfixes to
-- prevent memory leak.

-- Copyright (C) Yichun Zhang (agentzh)


require "resty.core.shdict"  -- enforce this to avoid dead locks

local shared = ngx.shared
local sleep = ngx.sleep
local max = math.max
local min = math.min
local setmetatable = setmetatable
local getmetatable = getmetatable
local newproxy = newproxy

local _M = { _VERSION = '0.08' }
local mt = { __index = _M }


local function _gc(proxy)
  local pmt = getmetatable(proxy)
  if pmt and pmt.__free and pmt.__table then
    pmt.__free(pmt.__table)
  end
end

local function gc_lock(self)
  if self.key then
    self.dict:delete(self.key)
  end
end

local function gctable(tbl)
  -- return an userdata with metatable
  local proxy = newproxy(true)
  -- store the reference of userdata in table
  -- so it's GC handler is called when table is GC'ed
  tbl.__proxy = proxy
  local pmt = getmetatable(proxy)
  pmt.__table = tbl
  pmt.__free = gc_lock
  pmt.__gc = _gc

  return tbl
end

function _M.new(_, dict_name, opts)
    local dict = shared[dict_name]
    if not dict then
        return nil, "dictionary not found"
    end

    local timeout, exptime, step, ratio, max_step
    if opts then
        timeout = opts.timeout
        exptime = opts.exptime
        step = opts.step
        ratio = opts.ratio
        max_step = opts.max_step
    end

    if not exptime then
        exptime = 30
    end

    if timeout then
        timeout = min(timeout, exptime)

        if step then
            step = min(step, timeout)
        end
    end

    local self = gctable({
        dict = dict,
	    key = nil,
        timeout = timeout or 5,
        exptime = exptime,
        step = step or 0.001,
        ratio = ratio or 2,
        max_step = max_step or 0.5,
    })
    setmetatable(self, mt)
    return self
end


function _M.lock(self, key)
    if not key then
        return nil, "nil key"
    end

    local dict = self.dict
    if self.key then
      return nil, "locked"
    end
    local exptime = self.exptime
    local ok, err = dict:add(key, true, exptime)
    if ok then
        self.key = key
        return 0
    end
    if err ~= "exists" then
        return nil, err
    end
    -- lock held by others
    local step = self.step
    local ratio = self.ratio
    local timeout = self.timeout
    local max_step = self.max_step
    local elapsed = 0
    while timeout > 0 do
        sleep(step)
        elapsed = elapsed + step
        timeout = timeout - step

        local ok, err = dict:add(key, true, exptime)
        if ok then
            self.key = key
            return elapsed
        end

        if err ~= "exists" then
            return nil, err
        end

        if timeout <= 0 then
            break
        end

        step = min(max(0.001, step * ratio), timeout, max_step)
    end

    return nil, "timeout"
end


function _M.unlock(self)
    local dict = self.dict
    local key = self.key

    if not key then
        return nil, "unlocked"
    end

    local ok, err = dict:delete(key)
    if not ok then
        return nil, err
    end
    self.key = nil

    return 1
end


function _M.expire(self, time)
    local dict = self.dict
    if not self.key then
      return nil, "unlocked"
    end

    if not time then
        time = self.exptime
    end

    local ok, err =  dict:replace(self.key, true, time)
    if not ok then
        return nil, err
    end

    return true
end

return _M
