-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

--AWS SAM Local Test Helper
local helpers = require "spec.helpers"
local utils = require "spec.helpers.perf.utils"
local fmt = string.format

local _M = {}


--- Get system architecture by uname
-- @function get_os_architecture
-- @return architecture string if success, or nil and an error message
function _M.get_os_architecture()
  local ret, err = utils.execute("uname -m")

  return ret, err
end


function _M.is_sam_installed()
  local ret, err = utils.execute("sam --version")
  if err then
    return nil, fmt("SAM CLI version check failed(code: %s): %s", err, ret)
  end

  return true
end


function _M.start_local_lambda()
  local port = helpers.get_available_port()
  if not port then
    return nil, "No available port found"
  end

  -- run in background
  local _ = ngx.thread.spawn(function()
    utils.execute("sam local start-lambda --template-file=spec/fixtures/sam-app/template.yaml --port " .. port)
  end)

  local ret, err = utils.execute("pgrep -f 'sam local'")
  if err then
    return nil, fmt("Start SAM CLI failed(code: %s): %s", err, ret)
  end

  return true, port
end


function _M.stop_local_lambda()
  local ret, err = utils.execute("pkill -f sam")
  if err then
    return nil, fmt("Stop SAM CLI failed(code: %s): %s", err, ret)
  end

  return true
end


return _M
