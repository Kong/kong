local conf_loader = require "kong.conf_loader"
local DAOFactory = require "kong.dao.factory"
local utils = require "kong.tools.utils"
local log = require "kong.cmd.utils.log"
local pl_string = require "pl.stringx"
local pl_pretty = require "pl.pretty"
local pl_table = require "pl.tablex"
local pl_path = require "pl.path"
local pl_file = require "pl.file"
local meta = require "kong.meta"
local pl_dir = require "pl.dir"
local cjson = require "cjson"

local EXCLUDE = { "nodes" }
local PAGE_SIZE = 100
local METADATA_FILE = ".kong_backup"

local ANSWERS = {
  y = true,
  Y = true,
  yes = true,
  YES = true,
  n = false,
  N = false,
  no = false,
  NO = false
}

local function confirm(q)
  local max = 3
  while max > 0 do
    io.write("> "..q.." [Y/n] ")
    local a = io.read("*l")
    if ANSWERS[a] ~= nil then
      return ANSWERS[a]
    end
    max = max - 1
  end
end

--- Calculates the dependency tree of the DAOs and returns them in the right order
local function order_daos(daos)
  local dependency_tree = {}

  -- Calculate dependencies
  for k, v in pairs(daos) do
    local deps = {}
    local schema = v.schema
    if schema and schema.fields then
      for _, v in pairs(schema.fields) do
        if v.foreign then
          table.insert(deps, pl_string.split(v.foreign, ":")[1])
        end
      end
    end
    dependency_tree[k] = deps
  end

  local keys = pl_table.keys(daos)
  table.sort(keys, function(a, b)
    if #dependency_tree[a] == 0 or #dependency_tree[b] == 0 then
      return #dependency_tree[a] < #dependency_tree[b]
    else
      return utils.table_contains(dependency_tree[b], a)
    end
  end)

  return keys
end

local function execute(args)
  local conf = assert(conf_loader(args.conf))
  local dao = DAOFactory(conf, conf.plugins)

  if args.command == "create" then
    -- Calculate amount of data to backup
    local total = 0
    for k, v in pairs(dao.daos) do
      if not utils.table_contains(EXCLUDE, k) and (not v.schema or (v.schema and not v.schema.no_backup)) then
        local count, err = v:count()
        if err then error(tostring(err)) end

        total = total + count
        log.verbose("* %s (%d)", k, count)
      else
        log.verbose("* %s (EXCLUDED)", k)
      end
    end
    if total == 0 then
      error("the database is empty")
      return
    end

    log("%d total entities to backup across %d tables", total, pl_table.size(dao.daos) - 1)
    if args.y or confirm("Are you sure? This operation may take a long time depending on the number of entities to backup") then

      -- Creating backup folder
      local tmp_dir = pl_path.join(conf.prefix, "backups", os.date("%Y_%m_%d_at_%H_%M_%S"))
      assert(not pl_path.exists(tmp_dir), "Backup already exists at: "..tmp_dir)
      log.verbose("creating temporary backup folder %s", tmp_dir)
      local ok, err = pl_dir.makepath(tmp_dir)
      if not ok then return nil, err end

      local meta_stats = {}
      -- Starting backup
      local total_size = 0
      for k, v in pairs(dao.daos) do
        local total = v:count()
        if not utils.table_contains(EXCLUDE, k) and total > 0 then
          local file_path = pl_path.join(tmp_dir, k)
          local file = assert(io.open(file_path, "a"))

          local index = 0
          local rows, err, offset
          repeat
            rows, err, offset = v:find_page(nil, offset, PAGE_SIZE)
            if err then error(tostring(err)) end

            for _, entity in ipairs(rows) do
              file:write(cjson.encode(entity).."\n")
              index = index + 1

              -- Print progress
              io.write(string.format("%s: %d/%d", k, index, total), "\r")
              io.flush()
            end
          until #rows == 0 or offset == nil

          log("%s: %d/%d", k, index, total)
          file:close()
          meta_stats[k] = { total=total }
          total_size = total_size + pl_path.getsize(file_path)
        end
      end

      -- Print metadata
      local file = assert(io.open(pl_path.join(tmp_dir, METADATA_FILE), "w"))
      file:write(cjson.encode({version = meta._VERSION, tables = meta_stats}))
      file:close()

      log("backup successfully created (%s) at: %s", pl_pretty.number(total_size, "M"), tmp_dir)
    else
      log("Canceled")
    end
  elseif args.command == "import" then
    
    -- Check folder
    local folder_path = args[1]
    assert(folder_path ~= nil, "must specify the folder path to import")
    assert(pl_path.exists(folder_path), "Backup not existing at: "..folder_path)

    -- Check metadata file
    local metadata_path = pl_path.join(folder_path, METADATA_FILE)
    assert(pl_path.exists(pl_path.join(folder_path, metadata_path)), "Backup is missing the metadata file")

    -- Check Kong version
    local metadata = assert(pl_file.read(metadata_path))
    local parsed_metadata = assert(cjson.decode(metadata))
    assert(parsed_metadata and parsed_metadata.version and parsed_metadata.tables, "Invalid metadata file")
    assert(parsed_metadata.version == meta._VERSION, "The backup is for a different version of Kong")

    if args.y or confirm("Are you sure? This operation is irreversible") then
      local ordered_daos = order_daos(dao.daos) -- Calculate dependency tree
      for _, v in ipairs(ordered_daos) do
        print(v)
        local dao = dao.daos[v]
        if not utils.table_contains(EXCLUDE, v) and (not dao.schema or (dao.schema and not dao.schema.no_backup)) then
          local file_path = pl_path.join(folder_path, v)
          if pl_path.exists(file_path) then
            local index = 0
            for line in io.lines(file_path) do
              local _, err = dao:insert(cjson.decode(line), {quiet = true})
              if err then
                error(tostring(err))
                return
              end
              index = index + 1
              -- Print progress
              io.write(string.format("%s: %d/%d", v, index, parsed_metadata.tables[v].total), "\r")
              io.flush()
            end
            log("%s: %d/%d", v, index, parsed_metadata.tables[v].total)
          end
        end
      end

      log("backup successfully imported")
    else
      log("Canceled")
    end
  end
end

local lapp = [[
Usage: kong backup COMMAND [OPTIONS]

Create or import backups of data stored in Kong.

The available commands are:
 create            Create a new backup from the database
 import <folder>   Import an existing backup into the database

Options:
 -c,--conf (optional string) configuration file
 -y        Assume yes; assume that the answer to any question which would be asked is yes
]]

return {
  lapp = lapp,
  execute = execute,
  sub_commands = {create = true, import = true}
}
