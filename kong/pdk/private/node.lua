local utils = require "kong.tools.utils"
local pl_file = require "pl.file"
local pl_path = require "pl.path"
local pl_dir = require "pl.dir"

local ngx = ngx

local cached_node_id

local function node_id_filename(prefix)
  return pl_path.join(prefix, "kong.id")
end


local function initialize_node_id(prefix)
  if not pl_path.exists(prefix) then
    local ok, err = pl_dir.makepath(prefix)
    if not ok then
      return false, "failed to create directory " .. prefix .. ": " .. err
    end
  end

  local filename = node_id_filename(prefix)

  if not pl_path.exists(filename) then
    local id = utils.uuid()
    ngx.log(ngx.INFO, "persisting node id " .. id .. " to filesystem ", filename)
    local ok, write_err = pl_file.write(filename, id)
    if not ok then
      return false, "failed to persist node id to filesystem " .. filename .. ": " .. write_err
    end
    cached_node_id = id
  end

  return true, nil
end


local function init_node_id(config)
  if not config then
    return
  end

  if not config.prefix or config.role ~= "data_plane" then
    return
  end

  local ok, err = initialize_node_id(config.prefix)
  if not ok then
    ngx.log(ngx.WARN, err)
  end
end


local function load_node_id(prefix)
  if not prefix then
    return nil, nil
  end

  if cached_node_id then
    return cached_node_id, nil
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
