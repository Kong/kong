local kong = kong

local api_routes = {}

if kong.configuration.wasm == false then

  local function wasm_disabled_error()
    return kong.response.exit(400, {
      message = "this endpoint is only available when wasm is enabled"
    })
  end

  api_routes = {
    ["/services/:services/filter-chains"] = {
      before = wasm_disabled_error,
    },

    ["/services/:services/filter-chains/:filter_chains"] = {
      before = wasm_disabled_error,
    },
  }

  return api_routes

end

return api_routes

