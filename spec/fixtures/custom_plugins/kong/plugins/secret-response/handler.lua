-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]


local kong_meta = require "kong.meta"
local decode = require "cjson".decode


local SecretResponse = {
  PRIORITY = 529,
  VERSION = kong_meta.core_version,
}


function SecretResponse:access()
  local reference = kong.request.get_query_arg("reference")
  local resp, err = kong.vault.get(reference)
  if not resp then
    return kong.response.exit(400, { message = err })
  end
  return kong.response.exit(200, decode(resp))
end


return SecretResponse
