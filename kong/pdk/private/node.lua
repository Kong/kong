local log = require "kong.cmd.utils.log"
local uuid = require "kong.tools.uuid"
local pl_file = require "pl.file"
local pl_path = require "pl.path"
local pl_dir = require "pl.dir"

local fmt = string.format

local cached_node_id

local function node_id_filename(prefix)
  return pl_path.join(prefix, "kong.id")
end


local function initialize_node_id(prefix)
  if not pl_path.exists(prefix) then
    local ok, err = pl_dir.makepath(prefix)
    if not ok then
      return nil, fmt("failed to create directory %s: %s", prefix, err)
    end
  end

  local filename = node_id_filename(prefix)

  local file_exists = pl_path.exists(filename)

  if file_exists then
    local id, err = pl_file.read(filename)
    if err then
      return nil, fmt("failed to access file %s: %s", filename, err)
    end

    if not uuid.is_valid_uuid(id) then
      log.debug("file %s contains invalid uuid: %s", filename, id)
      -- set false to override it when it contains an invalid uuid.
      file_exists = false
    end
  end

  if not file_exists then
    local id = uuid.uuid()
    log.debug("persisting node_id (%s) to %s", id, filename)

    local ok, write_err = pl_file.write(filename, id)
    if not ok then
      return nil, fmt("failed to persist node_id to %s: %s", filename, write_err)
    end
    cached_node_id = id
  end

  return true
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
    log.warn(err)
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
    return nil, fmt("file %s does not exist", filename)
  end

  local id, read_err = pl_file.read(filename)
  if read_err then
    return nil, fmt("failed to access file %s: %s", filename, read_err)
  end

  if not uuid.is_valid_uuid(id) then
    return nil, fmt("file %s contains invalid uuid: %q", filename, id)
  end

  return id, nil
end


return {
  init_node_id = init_node_id,
  load_node_id = load_node_id,
}
