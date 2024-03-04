-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local _M = {}

local etrace
local etrace_enter_span
local etrace_add_string_attribute
local etrace_add_bool_attribute
local etrace_add_int64_attribute
local etrace_add_double_attribute
local etrace_exit_span

local client = package.loaded["kong.resty.dns.client"]
if not client then
  client = require("kong.tools.dns")()
end


local function before_toip(qname, _port, _dnsCacheOnly, _try_list)
  etrace_enter_span("dns")
  etrace_add_string_attribute("qname", qname)
end


local function after_toip(ip_addr, res_port)
  etrace_add_int64_attribute("record.port", tonumber(res_port))

  if ip_addr then
    etrace_add_string_attribute("record.ip", ip_addr)
  end

  etrace_exit_span() -- dns
end


function _M.globalpatches(etrace_module)
  local req_dyn_hook = require("kong.dynamic_hook")

  --[[
    The `toip()` function can receive <= 4 arguments (including `self`).
    Here is the signature of the `toip()` function:
    function toip(self, qname, port, dnsCacheOnly, try_list)
  --]]
  req_dyn_hook.hook_function("etrace", client, "toip", 4, {
    befores = { before_toip },
    afters = { after_toip },
  })

  etrace = etrace_module
  etrace_enter_span = etrace.enter_span
  etrace_add_string_attribute = etrace.add_string_attribute
  etrace_add_bool_attribute = etrace.add_bool_attribute
  etrace_add_int64_attribute = etrace.add_int64_attribute
  etrace_add_double_attribute = etrace.add_double_attribute
  etrace_exit_span = etrace.exit_span
end


return _M
