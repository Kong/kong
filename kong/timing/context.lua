local cjson         = require("cjson.safe").new()

local ngx_get_phase = ngx.get_phase
local ngx_re_gmatch = ngx.re.gmatch

local math_floor    = math.floor
local setmetatable  = setmetatable
local table_insert  = table.insert
local table_remove  = table.remove

local time_ns       = require("kong.tools.time").time_ns

local assert        = assert

local _M            = {}
local _MT           = { __index = _M }

-- Set number precision smaller than 16 to avoid floating point errors
cjson.encode_number_precision(14)

function _M:enter_subcontext(name)
  assert(name ~= nil, "name is required")
  table_insert(self.sub_context_stack, self.current_subcontext)

  if not self.current_subcontext.child then
    self.current_subcontext.child = {}
  end

  if not self.current_subcontext.child[name] then
    self.current_subcontext.child[name] = {}
  end

  self.current_subcontext = self.current_subcontext.child[name]
  self.current_subcontext.____start____ = time_ns()
end


function _M:leave_subcontext(attributes)
  assert(#self.sub_context_stack > 0, "subcontext stack underflow")
  local elapsed = (time_ns() - self.current_subcontext.____start____) / 1e6
  local old_total_time = self.current_subcontext.total_time or 0
  self.current_subcontext.total_time = old_total_time + elapsed
  self.current_subcontext.____start____ = nil

  if attributes then
    for k, v in pairs(attributes) do
      _M:set_context_prop(k, v)
    end
  end

  self.current_subcontext = table_remove(self.sub_context_stack)
end


function _M:set_context_prop(k, v)
  assert(k ~= "total_time", "cannot set context key 'total_time' (reserved))")
  assert(k ~= "child", "cannot set context key 'child' (reserved))")
  assert(k ~= "____start____", "cannot set context key '____start____' (reserved))")

  self.current_subcontext[k] = v
end


function _M:get_context_kv(k)
  return self.current_subcontext[k]
end


function _M:get_root_context_kv(k)
  return self.root_context[k]
end


function _M:set_root_context_prop(k, v)
  self.root_context[k] = v
end


function _M:finalize(subcontext)
  -- finalize total_time optionally rounding to the nearest integer
  if subcontext.total_time then
    -- round to 2 decimal places
    subcontext.total_time = math_floor(subcontext.total_time * 100) / 100
  end

  if subcontext.child then
    for _, child in pairs(subcontext.child) do
      self:finalize(child)
    end
  end
end


function _M:get_total_time_without_upstream()
  local total_time = 0
  for k, child in pairs(self.root_context.child) do
    if k ~= "upstream" and child.total_time then
      total_time = total_time + child.total_time
    end
  end
  return total_time
end


function _M:to_json()
  local dangling = nil

  -- `> 1` means we have at least one subcontext (the root context)
  -- We always call this function at then end of the header_filter and
  -- log phases, so we should always have at least one subcontext.
  while #self.sub_context_stack > 1 do
    self:set_context_prop("dangling", true)
    self:leave_subcontext()
    dangling = true
  end

  if dangling then
    ngx.log(ngx.WARN, "timing: dangling subcontext(s) detected")
  end

  self:set_root_context_prop("dangling", dangling)
  self:finalize(self.root_context)
  if self.root_context.child ~= nil then
    self.root_context.total_time_without_upstream = self:get_total_time_without_upstream()
  end
  return assert(cjson.encode(self.root_context))
end


function _M:needs_logging()
  return self.log
end


function _M:from_loopback()
  return self.loopback
end


function _M:mock_upstream_phase()
  if not self.filter["upstream"] then
    return
  end

  -- time to first byte
  local tfb = ngx.ctx.KONG_WAITING_TIME
  if not tfb then
    -- route might not have been matched
    return
  end

  tfb = math_floor(tfb)

  if not self.root_context.child then
    self.root_context.child = {}
  end

  local phase = ngx_get_phase()

  if phase == "header_filter" then
    self.root_context.child.upstream = {
      total_time = tfb,
      child = {
        ["time_to_first_byte"] = {
          total_time = tfb,
        },
      }
    }

    return
  end

  if phase == "log" then
    local upstream_response_time = ngx.var.upstream_response_time

    if not upstream_response_time then
      return
    end

    -- upstream_response_time can be a comma-separated list of times
    if upstream_response_time:find(",", nil, true) then
      local itor = ngx_re_gmatch(upstream_response_time, [[(\d+)]], "jo")
      upstream_response_time = 0
      for m, err in itor do
        if err then
          return nil, err
        end

        -- upstream_response_time can also be a list that includes '-'
        local tmp = tonumber(m[1])
        upstream_response_time = upstream_response_time + (tmp or 0)
      end

    else
      -- upstream_response_time can also be a '-'
      upstream_response_time = tonumber(upstream_response_time)
      if not upstream_response_time then
        return
      end
    end

    upstream_response_time = math_floor(upstream_response_time * 1000)

    self.root_context.child.upstream.child.streaming = {
      total_time = math_floor(upstream_response_time - tfb),
    }

    self.root_context.child.upstream.total_time = upstream_response_time
    return
  end

  error("unexpected phase: " .. phase)
end


function _M:should_run()
  return self.filter[ngx_get_phase()]
end


function _M.new(filter, options)
  assert(options.log ~= nil, "options.log is required")
  assert(options.loopback ~= nil, "options.loopback is required")

  local self = {
    current_subcontext = nil,
    root_context = {},
    sub_context_stack = {},
    log = options.log, -- print to the error_log?
    loopback = options.loopback, -- request from the loopback?
    filter = filter,
  }

  self.current_subcontext = self.root_context
  self.current_subcontext_name = "root"
  return setmetatable(self, _MT)
end

return _M
