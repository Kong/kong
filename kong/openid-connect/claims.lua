-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]




local function table_pairs_len(tbl)
  local count = 0
  for _ in pairs(tbl) do count = count + 1 end
  return count
end

local ClaimsHandler = {}

ClaimsHandler.__index = ClaimsHandler

--- Creates ClaimsHandler instance
-- @function new
-- @param tokens (table) tokens containing all known tokens (ID, access_token, refresh)
-- @param oic (table) the instance of a openid-connect.oic
-- @return self
function ClaimsHandler.new(idt, act, oic)
  local self = setmetatable({}, ClaimsHandler)
  self.access_token = act
  self.id_token = idt
  self.payload = self:get_payload()
  self.oic = oic
  return self
end

--- Gets payload from the ID token
-- @function get_payload
-- @return payload(table)
function ClaimsHandler:get_payload()
  if self.id_token ~= nil then
    return self.id_token.payload
  end
  return {}
end

--- Validates attributes for a give distributed claim source table
-- @function check_claim_meta
-- @param claim_meta (table) a source table for a distributed claim
-- @return status(nil|boolean), error(string)
function ClaimsHandler.check_claim_meta(claim_meta)
  -- The minimum requirement for a distributed claim is an `endpoint` attribute
  if not claim_meta.endpoint then
    return nil, "Could not find endpoint"
  end
  return true, nil
end

--- Queries the endpoint in a distributed claim
-- @function query_endpoint
-- @param claim_meta (table) a source table for a distributed claim
-- @return res (table), error(string)
function ClaimsHandler:query_endpoint(claim_meta)
  local access_token = claim_meta.access_token or self.access_token
  if not access_token then
    return nil, "Contacting a userinfo_endpoint without an access_token is currently not supported"
  end
  local res, err, _ = self.oic:userinfo(access_token, {userinfo_endpoint=claim_meta.endpoint})
  return res, err
end

--- Resolve aggregated claims
-- @function resolve_aggregated_claims
-- @return status(nil|boolean), error(string)
function ClaimsHandler.resolve_aggregated_claims()
  -- for future implementations
  return nil, "Not implemented"
end

--- Resolve distributed claims
-- @function resolve_distributed_claims
-- @return status(nil|boolean), error(string)
function ClaimsHandler:resolve_distributed_claims()
  local claim_names = self.payload._claim_names
  local claim_sources = self.payload._claim_sources

  -- no distributed claims found.
  if claim_names == nil then
    return true, nil
  end

  if type(claim_names) ~= "table" then
    return nil, "_claim_names must be of type table"
  end

  if claim_sources == nil then
    return nil, "Found _claim_names but no _claim_sources in payload."
  end

  if type(claim_sources) ~= "table" then
    return nil, "_claim_names must be of type table"
  end

  local res, _err = self:resolve_references()
  if not res and _err then
    return nil, _err
  end

  -- success, no errors
  return true, nil
end

--- Resolve references in a given JWS payload
-- @function resolve_references
-- @return status(nil|boolean), error(string)
function ClaimsHandler:resolve_references()
  local claim_names = self.payload._claim_names
  local claim_sources = self.payload._claim_sources
  for claim_name, claim_ref in pairs(claim_names) do
    local found = false
    for claim_source, claim_meta in pairs(claim_sources) do
      if claim_ref == claim_source then
        found = true
        -- claim already exists in the payload
        if self.payload[claim_name] ~= nil then
          return nil,
            string.format("Requested claim <%s> already exists in \
                          the payload. Retrieving it would overwrite \
                          the existing one.", claim_name)
        end
        -- check if required fields are present
        local meta_check, claim_check_err = self.check_claim_meta(claim_meta)
        if not meta_check and claim_check_err then
          return nil, claim_check_err
        end
        -- query endpoint
        local deref, deref_err = self:query_endpoint(claim_meta)
        if not deref or deref_err then
          return nil, deref_err
        end

        -- AzureAD specifics.
        -- endpoint return a table structure with a single `value` key.
        -- we can only safely assume that the `value` is what we're looking for
        -- if there is only one claim_name.
        if deref["value"] then
          -- and there is only a single claim_name
          if table_pairs_len(claim_names) == 1 then
            -- swap and break
            self.payload[claim_name] = deref["value"]
            break
          else
            return nil, "Found <value> in response but could not decide which claim_name to assign it to."
          end
        end

        -- check if requested claim_name is present in returned json
        if not deref[claim_name] then
          return nil, string.format("Could not find claim <%s> in endpoint return", claim_name)
        end
        -- assign the requested field `claim_name` with the corresponding value
        self.payload[claim_name] = deref[claim_name]
        break
      end
    end
    -- fail even if one reference can't be resolved
    if not found then
      return nil, string.format("Could not find reference for %s", claim_name)
    end
    -- finally remove the reference pointers
    -- luacheck:ignore 143
    self.payload._claim_sources = nil
    self.payload._claim_names = nil
  end
end


return ClaimsHandler
