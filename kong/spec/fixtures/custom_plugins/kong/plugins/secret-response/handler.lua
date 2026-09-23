local kong_meta = require "kong.meta"
local decode = require "cjson".decode


local SecretResponse = {
  PRIORITY = 529,
  VERSION = kong_meta.version,
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
