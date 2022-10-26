local utils = require "kong.tools.utils"
local pl_file = require "pl.file"
local pl_path = require "pl.path"

local ngx = ngx
local subsystem = ngx.config.subsystem


local function node_id_filename(prefix)
  return pl_path.join(prefix, "/kong.id")
end

local function initialize_node_id(prefix)
  local filename = node_id_filename(prefix)

  if not pl_path.exists(filename) then
    local id = utils.uuid()
    ngx.log(ngx.INFO, "persisting node id " .. id .. " to filesystem ", filename)
    local ok, write_err = pl_file.write(filename, id)
    if not ok then
      return "failed to persist node id to filesystem " .. filename .. ": " .. write_err
    end
  end
end

local function init_node_id(config)
  local prefix = config and config.prefix or nil
  if not prefix then
    return
  end

  local err = initialize_node_id(prefix)
  if err then
    ngx.log(ngx.WARN, err)
  end
end

local function load_node_id(prefix)
  if not prefix then
    return nil, nil
  end

  if subsystem == "stream" then
    return nil, nil
  end

  local filename = node_id_filename(prefix)

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
