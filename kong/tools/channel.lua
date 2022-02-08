
local min = math.min
local max = math.max

local now = ngx.now
local sleep = ngx.sleep

local DEFAULT_EXPTIME = 3600
local DEFAULT_TIMEOUT = 5
local NAME_KEY = "channel_up"
local POST_VAL_KEY_PREFIX = "channel_post_value_"
local RESP_VAL_KEY_PREFIX = "channel_resp_value_"


local function waitstep(step, deadline)
  sleep(step)
  return min(max(0.001, step * 2), deadline-now(), 0.5)
end

--- waiting version of `d:add()`
--- blocks the coroutine until there's no value under this key
--- so the new value can be safely added
local function add_wait(dict, key, val, exptime, deadline)
  local step = 0

  while deadline > now() do
    local ok, err = dict:add(key, val, exptime)
    if ok then
      return true
    end

    if err ~= "exists" then
      return nil, err
    end

    step = waitstep(step, deadline)
  end

  return nil, "timeout"
end

--- waiting version of `d:get()`
--- blocks the coroutine until there's actually a value under this key
local function get_wait(dict, key, deadline)
  local step = 0

  while deadline > now() do
    local value, err = dict:get(key)
    if value then
      return value
    end

    if err ~= nil then
      return nil, err
    end

    step = waitstep(step, deadline)
  end

  return nil, "timeout"
end

--- waits until the key is empty
--- blocks the coroutine while there's a value under this key
local function empty_wait(dict, key, deadline)
  local step = 0
  while deadline > now() do
    local value, err = dict:get(key)
    if not value then
      if err ~= nil then
        return nil, err
      end

      return true
    end

    step = waitstep(step, deadline)
  end
  return nil, "timeout"
end


local Channel = {}
Channel.__index = Channel

--- Create a new channel client
--- @param dict_name string Name of the shdict to use
--- @param name string channel name
function Channel.new(dict_name, name)
  return setmetatable({
    dict = assert(ngx.shared[dict_name]),
    name = name,
    exptime = DEFAULT_EXPTIME,
    timeout = DEFAULT_TIMEOUT,
  }, Channel)
end


--- Post a value, client -> server
--- blocks the thread until the server picks it
--- @param val any Value to post (any type supported by shdict)
--- @return boolean, string ok, err
function Channel:post(val)
  local key = POST_VAL_KEY_PREFIX .. self.name
  local ok, err = add_wait(self.dict, key, val, self.exptime, now() + self.timeout)
  if not ok then
    return nil, err
  end

  ok, err = add_wait(self.dict, NAME_KEY, self.name, self.exptime, now() + self.timeout)
  if not ok then
    self.dict:delete(key)
    return nil, err
  end

  return empty_wait(self.dict, key, now() + self.timeout)
end

--- Get a response value, client <- server
--- blocks the thread until the server puts a value
--- @return any, string value, error
function Channel:get()
  local key = RESP_VAL_KEY_PREFIX .. self.name
  local val, err = get_wait(self.dict, key, now() + self.timeout)
  if val then
    self.dict:delete(key)
    return val
  end

  return nil, err
end


--- Waits until a value is posted by any client
--- @param dict shdict shdict to use
--- @return any, string, string value, channel name, error
function Channel.wait_all(dict)
  local name, err = get_wait(dict, NAME_KEY, now() + DEFAULT_TIMEOUT)
  if not name then
    return nil, nil, err
  end

  local key = POST_VAL_KEY_PREFIX .. name
  local val
  val, err = get_wait(dict, key, now() + DEFAULT_TIMEOUT)
  dict:delete(key)
  dict:delete(NAME_KEY)

  return val, name, err
end


--- Put a response value server -> client
--- @param dict shdict shdict to use
--- @param name string channel name
--- @param val any Value to put (any type supported by shdict)
--- @return boolean, string ok, error
function Channel.put_back(dict, name, val)
  local key = RESP_VAL_KEY_PREFIX .. name
  return add_wait(dict, key, val, DEFAULT_EXPTIME, now() + DEFAULT_TIMEOUT)
end


return Channel
