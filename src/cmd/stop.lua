#!/usr/bin/env lua

local utils = require "kong.cmd.utils"
local args = require "lapp" [[

Usage: kong stop [options]

Options:
  -o,--output (default nginx_tmp) nginx output
]]

local pid = utils.path:join(args.output, "nginx.pid")

if not utils.file_exists(pid) then
 utils.logger:error_exit("NOT RUNNING")
end

local cmd = "kill $(cat "..pid..")"

return os.execute(cmd)
