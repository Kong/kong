local constants = require "kong.constants"
local vault_loader = require "kong.db.schema.vault_loader"
local load_module_if_exists = require "kong.tools.module".load_module_if_exists


local Vaults = {}


local type = type
local pairs = pairs
local concat = table.concat
local insert = table.insert
local tostring = tostring
local log = ngx.log


local WARN = ngx.WARN
local DEBUG = ngx.DEBUG


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


function Vaults:cache_key(prefix)
  if type(prefix) == "table" then
    prefix = prefix.prefix
  end

  -- Always return the cache_key without a workspace because prefix is unique across workspaces
  return "vaults:" .. prefix .. ":::::"
end


return Vaults
