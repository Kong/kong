local _M = {}
local request_querystring_factory = require "kong.plugins.metadata-insertion.factory.request_querystring_factory"
local request_headers_factory = require "kong.plugins.metadata-insertion.factory.request_headers_factory"
-- local debug = require "kong.plugins.metadata-insertion.tool.debug"
local cache = require "kong.tools.database_cache"
local singletons = require "kong.singletons"
local responses = require "kong.tools.responses"
local currentUserMetadata

local function getPersistentMetadata()
  -- retrieve metadata from cache or database for current user
  currentUserMetadata = cache.get_or_set("metadata_keyvaluestore." .. ngx.ctx.authenticated_consumer.id, nil, function()
    local metadata, err = singletons.dao.metadata_keyvaluestore:find_all({ consumer_id = ngx.ctx.authenticated_consumer.id })
    if err then
      return responses.send_HTTP_INTERNAL_SERVER_ERROR(err)
    end
    return metadata
  end)

  if currentUserMetadata then
    return currentUserMetadata
  end

  return {}
end

local function resolveParameterValuePlaceholderWithMetadata(dataProvisioningName)
  for _, elem in ipairs(currentUserMetadata) do
    if elem.key == dataProvisioningName then
      return elem.value
    end
  end
  error("This API needs metadata that the current user does not provide.")
end

local function retrieveMetadataForConfigToken(querystringModifier)
  local args = {}

  for stringChunk in string.gmatch(querystringModifier, "%S+") do
    table.insert(args, stringChunk)
  end

  assert(table.getn(args) == 2, "Invalid format")

  -- Prepare arg name
  local argName = args[1]
  argName = argName:gsub(":", "")

  -- Prepare arg value (replace placeholder name by metadata value)
  local argValuePlaceholderName = args[2]
  argValuePlaceholderName = argValuePlaceholderName:gsub("%%", "")
  local parameterValue = resolveParameterValuePlaceholderWithMetadata(argValuePlaceholderName)
  return argName, parameterValue
end


local function appendMetadataFromTransitoryStore(currentUserMetadata)

  -- loop through transitory store and add the metadata in memory
  -- transitory store take precedence over persitent metadata
  if ngx.ctx.metadata_transitory_store and type(ngx.ctx.metadata_transitory_store) == "table" then

    for _, transitoryStoreElem in ipairs(ngx.ctx.metadata_transitory_store) do

      local persistentMetadataFound = false

      -- replace persitent metadata with transitory store if it exist in both place
      for index, persistentMetadataElem in ipairs(currentUserMetadata) do
        if persistentMetadataElem.key == transitoryStoreElem.key then
          currentUserMetadata[index] = transitoryStoreElem
          persistentMetadataFound = true
        end
      end

      -- if nothing found in persistent metadata, let's make sure we add the transitory store element as new
      if persistentMetadataFound == false then
        table.insert(currentUserMetadata, transitoryStoreElem)
      end
    end
  end
end

local function updateQuerystring(confDataInsertion)

  local RequestQuerystringFactory = request_querystring_factory:new()

  RequestQuerystringFactory:mergeArgsWithRequestArgs()

  -- Remove querystring(s)
  if confDataInsertion.remove and confDataInsertion.remove.querystring then
    for _, key in ipairs(confDataInsertion.remove.querystring) do
      RequestQuerystringFactory:removeArgByKey(key)
    end
  end

  -- Replace querystring(s)
  if confDataInsertion.replace and confDataInsertion.replace.querystring then
    for _, querystringModifier in pairs(confDataInsertion.replace.querystring) do
      local parameterName, parameterValue = retrieveMetadataForConfigToken(querystringModifier)
      RequestQuerystringFactory:replaceArgByKey(parameterName, parameterValue)
    end
  end

  -- Add querystring(s)
  if confDataInsertion.add and confDataInsertion.add.querystring then
    for _, querystringModifier in pairs(confDataInsertion.add.querystring) do
      local parameterName, parameterValue = retrieveMetadataForConfigToken(querystringModifier)
      RequestQuerystringFactory:add(parameterName, parameterValue)
    end
  end

  RequestQuerystringFactory:persist()
end

local function updateHeaders(confDataInsertion)

  local RequestHeadersFactory = request_headers_factory:new()

  RequestHeadersFactory:mergeArgsWithRequestArgs()

  -- Remove querystring(s)
  if confDataInsertion.remove and confDataInsertion.remove.headers then
    for _, key in ipairs(confDataInsertion.remove.headers) do
      RequestHeadersFactory:removeArgByKey(key)
    end
  end

  -- Replace querystring(s)
  if confDataInsertion.replace and confDataInsertion.replace.headers then
    for _, headersModifier in pairs(confDataInsertion.replace.headers) do
      local parameterName, parameterValue = retrieveMetadataForConfigToken(headersModifier)
      RequestHeadersFactory:replaceArgByKey(parameterName, parameterValue)
    end
  end

  -- Add querystring(s)
  if confDataInsertion.add and confDataInsertion.add.headers then
    for _, headersModifier in pairs(confDataInsertion.add.headers) do
      local parameterName, parameterValue = retrieveMetadataForConfigToken(headersModifier)
      RequestHeadersFactory:add(parameterName, parameterValue)
    end
  end

  RequestHeadersFactory:persist()
end

function _M.execute(conf)

  if ngx.ctx.authenticated_consumer == nil then
    return responses.send_HTTP_UNAUTHORIZED("Metadata plugin can't be used without having an authenticated user.")
  end

  currentUserMetadata = getPersistentMetadata()
  appendMetadataFromTransitoryStore(currentUserMetadata)

  local _, err = pcall(function()

    -----------------------------
    -- Data Insertion Processing
    -----------------------------
    updateQuerystring(conf)
    updateHeaders(conf)
  end)

  if err then
    return responses.send_HTTP_BAD_REQUEST(err)
  end
end

return _M