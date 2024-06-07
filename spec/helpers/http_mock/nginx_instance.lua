--- part of http_mock
-- @submodule spec.helpers.http_mock

local template_str = require "spec.helpers.http_mock.template"
local pl_template = require "pl.template"
local pl_path = require "pl.path"
local pl_dir = require "pl.dir"
local pl_file = require "pl.file"
local pl_utils = require "pl.utils"
local shell = require "resty.shell"

local print = print
local error = error
local assert = assert
local ngx = ngx
local io = io

local shallow_copy
do
  local clone = require "table.clone"

  shallow_copy = function(orig)
    assert(type(orig) == "table")
    return clone(orig)
  end
end

local template = assert(pl_template.compile(template_str))
local render_env = {ipairs = ipairs, pairs = pairs, error = error, }
local http_mock = {}

--- start a dedicate nginx instance for this mock
-- @tparam[opt=false] bool error_on_exist whether to throw error if the directory already exists
-- @within http_mock
-- @usage http_mock:start(true)
function http_mock:start(error_on_exist)
  local ok = (pl_path.mkdir(self.prefix))
    and (pl_path.mkdir(self.prefix .. "/logs"))
    and (pl_path.mkdir(self.prefix .. "/conf"))
  if error_on_exist then assert(ok, "failed to create directory " .. self.prefix) end

  local render = assert(template:render(shallow_copy(self), render_env))
  local conf_path = self.prefix .. "/conf/nginx.conf"
  local conf_file = assert(io.open(conf_path, "w"))
  assert(conf_file:write(render))
  assert(conf_file:close())

  local cmd = "nginx -p " .. self.prefix
  local ok, code, _, stderr = pl_utils.executeex(cmd)
  assert(ok and code == 0, "failed to start nginx: " .. stderr)
  return true
end

local sleep_step = 0.01

--- stop a dedicate nginx instance for this mock
-- @function http_mock:stop
-- @tparam[opt=false] bool no_clean whether to preserve the logs
-- @tparam[opt="TERM"] string signal the signal name to send to the nginx process
-- @tparam[opt=10] number timeout the timeout to wait for the nginx process to exit
-- @within http_mock
-- @usage http_mock:stop(false, "TERM", 10)
function http_mock:stop(no_clean, signal, timeout)
  signal = signal or "TERM"
  timeout = timeout or 10
  local pid_filename = self.prefix .. "/logs/nginx.pid"
  local pid_file = assert(io.open(pid_filename, "r"))
  local pid = assert(pid_file:read("*a"))
  pid_file:close()

  local kill_nginx_cmd = "kill -s " .. signal .. " " .. pid
  if not shell.run(kill_nginx_cmd, nil, 0) then
    error("failed to kill nginx at " .. self.prefix, 2)
  end

  local time = 0
  while pl_file.access_time(pid_filename) ~= nil do
    ngx.sleep(sleep_step)
    time = time + sleep_step
    if(time > timeout) then
      error("nginx does not exit at " .. self.prefix, 2)
    end
  end

  if no_clean then return true end

  local _, err = pl_dir.rmtree(self.prefix)
  if err then
    print("could not remove ", self.prefix, ": ", tostring(err))
  end

  return true
end

return http_mock
