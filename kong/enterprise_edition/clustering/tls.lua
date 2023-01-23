-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]


-- EE-specific helper functions for hybrid mode
local tls = {}


local utils = require("kong.tools.utils")

local match = string.match
local get_cn_parent_domain = utils.get_cn_parent_domain


local common_name_allowed
do
  -- NOTE: using the config object as a cache key is not strictly necessary,
  -- but it's harmless and makes testing easier because the cached lookup table
  -- is invalidated for each unit test case that presents a different config.
  --
  ---@type table<table, table<string, boolean>>
  local cache = setmetatable({}, { __mode = "k" })

  ---@param kong_config table
  ---@param cp_cert     kong.clustering.certinfo
  ---@param dp_x509     table
  ---
  ---@return boolean  success
  ---@return string?  error
  function common_name_allowed(kong_config, cp_cert, dp_x509)
    local dp_cn, err = get_cn_parent_domain(dp_x509)
    if not dp_cn then
      return false, "data plane presented incorrect client certificate " ..
                    "during handshake, unable to extract CN: " .. tostring(err)
    end

    local allowed = cache[kong_config]

    -- lazily build common name lookup table
    if not allowed then
      if kong_config.cluster_allowed_common_names and
        #kong_config.cluster_allowed_common_names > 0
      then
        allowed = {}

        for _, name in ipairs(kong_config.cluster_allowed_common_names) do
          allowed[name] = true
        end

      else
        -- in the absence of a list of explicitly allowed common names, we will
        -- match against the parent domain of the CP cluster cert
        allowed = setmetatable({}, {
          __index = function(_, k)
            return match(k, "^[%a%d-]+%.(.+)$") == cp_cert.parent_common_name
          end
        })
      end

      cache[kong_config] = allowed
    end

    if allowed[dp_cn] then
      return true

    else
      return false, "data plane presented client certificate with incorrect " ..
                    "CN during handshake, got: " .. dp_cn

    end
  end
end


--- Validate the client certificate presented by a data plane.
---
--- This function performs additional validation for EE-specific features.
---
---@param kong_config table
---@param cp_cert     kong.clustering.certinfo
---@param dp_x509     table
---
---@return boolean  success
---@return string?  error
function tls.ee_validate_client_cert(kong_config, cp_cert, dp_x509)
  if kong_config.cluster_mtls == "pki_check_cn" then
    local allow, err = common_name_allowed(kong_config, cp_cert, dp_x509)
    if not allow then
      return false, err
    end
  end

  return true
end


return tls
