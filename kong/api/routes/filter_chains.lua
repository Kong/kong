local kong = kong


local api_routes = {}

if kong.configuration.wasm == false then

  local function wasm_disabled_error()
    return kong.response.exit(400, {
      message = "this endpoint is only available when wasm is enabled"
    })
  end

  api_routes = {
    ["/filter-chains"] = {
      before = wasm_disabled_error,
    },

    ["/filter-chains/:filter_chains"] = {
      before = wasm_disabled_error,
    },

    ["/filter-chains/:filter_chains/route"] = {
      before = wasm_disabled_error,
    },

    ["/filter-chains/:filter_chains/service"] = {
      before = wasm_disabled_error,
    },

    ["/routes/:routes/filter-chains"] = {
      before = wasm_disabled_error,
    },

    ["/routes/:routes/filter-chains/:filter_chains"] = {
      before = wasm_disabled_error,
    },

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

