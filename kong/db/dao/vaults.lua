local constants = require "kong.constants"
local vault_loader = require "kong.db.schema.vault_loader"
local load_module_if_exists = require "kong.tools.module".load_module_if_exists
local is_vault_reference = require("kong.pdk.vault").is_reference
local list_concat = require("kong.tools.table").concat
local yield = require("kong.tools.yield").yield


local Vaults = {}


local type = type
local pairs = pairs
local concat = table.concat
local insert = table.insert
local tostring = tostring
local log = ngx.log


local WARN = ngx.WARN
local DEBUG = ngx.DEBUG

local GLOBAL_QUERY_OPTS = { nulls = true, workspace = ngx.null }


local function load_vault_strategy(vault)
  local ok, strategy = load_module_if_exists("kong.vaults." .. vault)
  if not ok then
    return nil, vault .. " vault is enabled but not installed;\n" .. strategy
  end

  return strategy
end


local function load_vault(self, vault)
  local db = self.db

  if constants.DEPRECATED_VAULTS[vault] then
    log(WARN, "vault '", vault, "' has been deprecated")
  end

  local strategy, err = load_vault_strategy(vault)
  if not strategy then
    return nil, err
  end

  if type(strategy.init) == "function" then
    strategy.init()
  end

  local _, err = vault_loader.load_subschema(self.schema, vault, db.errors)
  if err then
    return nil, err
  end

  log(DEBUG, "Loading vault: ", vault)

  return strategy
end


--- Load subschemas for enabled vaults into the Vaults entity. It has two side effects:
--  * It makes the Vault sub-schemas available for the rest of the application
--  * It initializes the Vault.
-- @param vault_set a set of vault names.
-- @return true if success, or nil and an error message.
function Vaults:load_vault_schemas(vault_set)
  local strategies = {}
  local errors

  for vault in pairs(vault_set) do
    local strategy, err = load_vault(self, vault)
    if strategy then
      strategies[vault] = strategy
    else
      errors = errors or {}
      insert(errors, "on vault '" .. vault .. "': " .. tostring(err))
    end
  end

  if errors then
    return nil, "error loading vault schemas: " .. concat(errors, "; ")
  end

  self.strategies = strategies

  return true
end


local function find_vault_references(tab)
  local refs = {}
  for k, v in pairs(tab) do
    local kt = type(k)
    if kt == "table" then
      refs = list_concat(refs, find_vault_references(k))

    elseif kt == "string" and is_vault_reference(k) then
      refs[#refs+1] = k
    end

    local vt = type(v)
    if vt == "table" then
      refs = list_concat(refs, find_vault_references(v))

    elseif vt == "string" and is_vault_reference(v) then
      refs[#refs+1] = v
    end
  end

  return refs
end


function Vaults:find_references_in_entities()
  local references = {}
  local db = kong.db
  for _, dao in pairs(db.daos) do
    local schema = dao.schema
    local name = schema.name
    local page_size = db[name].pagination and db[name].pagination.max_page_size
    for row, err in db[name]:each(page_size, GLOBAL_QUERY_OPTS) do
      yield()
      if not row then
        kong.log.err(err)
        return nil, err
      end

      -- references = list_concat(references, find_vault_references(row))
      for _, ref in ipairs(find_vault_references(row)) do
        references[ref] = true
      end
    end
  end

  return references
end


return Vaults
