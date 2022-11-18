--AWS SAM Local Test Helper
local helpers = require "spec.helpers"
local utils = require "spec.helpers.perf.utils"
local fmt = string.format

local SAM_CLI_ZIP_URL = "https://github.com/aws/aws-sam-cli/releases/latest/download/aws-sam-cli-linux-x86_64.zip"

local _M = {}


--- Get system architecture by uname
-- @function get_os_architecture
-- @return architecture string if success, or nil and an error message
function _M.get_os_architecture()
  local ret, err = utils.execute("uname -m")

  return ret, err
end


function _M.setup()
  local ret, err = utils.execute("curl -L -s -o /tmp/aws-sam-cli.zip " .. SAM_CLI_ZIP_URL)
  if err then
    return nil, fmt("Dowloading SAM CLI failed(code: %s): %s", err, ret)
  end

  ret, err = utils.execute("unzip -o /tmp/aws-sam-cli.zip -d /tmp/aws-sam-cli")
  if err then
    return nil, fmt("Unzip SAM CLI failed(code: %s): %s", err, ret)
  end

  ret, err = utils.execute("/tmp/aws-sam-cli/install")
  if err then
    return nil, fmt("Install SAM CLI failed(code: %s): %s", err, ret)
  end

  ret, err = utils.execute("sam --version")
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
