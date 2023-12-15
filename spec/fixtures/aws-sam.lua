--AWS SAM Local Test Helper
local ngx_pipe = require "ngx.pipe"
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


local sam_proc


function _M.start_local_lambda()
  local port = helpers.get_available_port()
  if not port then
    return nil, "No available port found"
  end

  -- run in background
  local err
  sam_proc, err = ngx_pipe.spawn({"sam",
        "local",
        "start-lambda",
        "--template-file", "spec/fixtures/sam-app/template.yaml",
        "--port", port
  })
  if not sam_proc then
     return nil, err
  end

  local ret, err = utils.execute("pgrep -f 'sam local'")
  if err then
    return nil, fmt("Start SAM CLI failed(code: %s): %s", err, ret)
  end

  return true, port
end


function _M.stop_local_lambda()
  if sam_proc then
     local ok, err = sam_proc:kill(15)
     if not ok then
        return nil, fmt("Stop SAM CLI failed: %s", err)
     end
     sam_proc = nil
  end

  return true
end


return _M
