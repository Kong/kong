local IO = require "kong.tools.io"
local utils = require "kong.tools.utils"
local singletons = require "kong.singletons"

local _M = {}

local IDENTIFIER = "serf.id"

function _M.get_node_identifier(conf)
  local id = singletons.serf_id
  if not id then
    id = IO.read_file(IO.path:join(conf.nginx_working_dir, IDENTIFIER))
    singletons.serf_id = id
  end
  return id
end

function _M.create_node_identifier(conf)
  local path = IO.path:join(conf.nginx_working_dir, IDENTIFIER)
  if not IO.file_exists(path) then
    local id = utils.get_hostname().."_"..conf.cluster_listen.."_"..utils.random_string()
    local _, err = IO.write_to_file(path, id)
    if err then
      return false, err
    end
  end
  return true
end

return _M