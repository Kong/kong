local utils = require "kong.tools.utils"
local pl_file = require "pl.file"
local pl_path = require "pl.path"
local pl_dir = require "pl.dir"

local ngx = ngx


local function init_mode_node_id(prefix, mode)
  local path = pl_path.join(prefix, "node.id")
  local filename = pl_path.join(path, mode)

  if not pl_path.exists(path) then
    local ok, err = pl_dir.makepath(path)
    if not ok then
      return "failed to create directory " .. path .. ": " .. err
    end
  end

  if not pl_path.exists(filename) then
    local id = utils.uuid()
    ngx.log(ngx.INFO, "persisting node id " .. id .. " to filesystem ", filename)
    local ok, write_err = pl_file.write(filename, id)
    if not ok then
      return "failed to persist node id to filesystem " .. filename .. ": "  .. write_err
    end
  end
end


local init_node_id = function(config)
  local prefix = config and config.prefix
  if not prefix then
    return
  end

  local modes = { "http", "stream" }
  for _, mode in ipairs(modes) do
    local err = init_mode_node_id(prefix, mode)
    if err then
      ngx.log(ngx.WARN, err)
    end
  end
end


local function load_node_id(prefix)
  local mode = ngx.config.subsystem
  local filename = pl_path.join(prefix, "node.id", mode)

  if not pl_path.exists(filename) then
    return nil, "file does not exist: " .. filename
  end

  local id, read_err = pl_file.read(filename)
  if read_err then
    return nil, string.format("failed to access file %s: %s", filename, read_err)
  end

  if not utils.is_valid_uuid(id) then
    return nil, "invalid uuid in file " .. filename
  end

  return id, nil
end


return {
  init_node_id = init_node_id,
  load_node_id = load_node_id,
}
