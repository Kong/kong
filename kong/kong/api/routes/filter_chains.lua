local cjson = require "cjson"
local endpoints = require "kong.api.endpoints"


local kong = kong


if kong.configuration.wasm == false then

  local function wasm_disabled_error()
    return kong.response.exit(400, {
      message = "this endpoint is only available when wasm is enabled"
    })
  end

  return {
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

    -- foreign key endpoints:

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

    -- custom endpoints (implemented below):

    ["/routes/:routes/filters/enabled"] = {
      GET = wasm_disabled_error,
    },

    ["/routes/:routes/filters/disabled"] = {
      GET = wasm_disabled_error,
    },

    ["/routes/:routes/filters/all"] = {
      GET = wasm_disabled_error,
    },
  }
end


local function add_filters(filters, chain, from)
  if not chain then
    return
  end

  for _, filter in ipairs(chain.filters) do
    table.insert(filters, {
      name = filter.name,
      config = filter.config,
      from = from,
      enabled = (chain.enabled == true and filter.enabled == true),
      filter_chain = {
        name = chain.name,
        id = chain.id,
      }
    })
  end
end


local function get_filters(self, db)
  local route, _, err_t = endpoints.select_entity(self, db, db.routes.schema)
  if err_t then
    return nil, err_t
  end

  if not route then
    return kong.response.exit(404, { message = "Not found" })
  end

  local route_chain
  for chain, _, err_t in kong.db.filter_chains:each_for_route(route, nil, { nulls = true }) do
    if not chain then
      return nil, err_t
    end

    route_chain = chain
  end

  local service
  local service_chain

  if route.service then
    service , _, err_t = kong.db.services:select(route.service)
    if err_t then
      return nil, err_t
    end

    for chain, _, err_t in kong.db.filter_chains:each_for_service(service, nil, { nulls = true }) do
      if not chain then
        return nil, err_t
      end

      service_chain = chain
    end
  end

  local filters = setmetatable({}, cjson.array_mt)
  add_filters(filters, service_chain, "service")
  add_filters(filters, route_chain, "route")

  return filters
end


return {
  ["/routes/:routes/filters/all"] = {
    GET = function(self, db)
      local filters, err_t = get_filters(self, db)
      if err_t then
        return endpoints.handle_error(err_t)
      end

      return kong.response.exit(200, {
        filters = filters,
      })
    end
  },

  ["/routes/:routes/filters/enabled"] = {
    GET = function(self, db)
      local filters, err_t = get_filters(self, db)
      if err_t then
        return endpoints.handle_error(err_t)
      end

      for i = #filters, 1, -1 do
        if not filters[i].enabled then
          table.remove(filters, i)
        end
      end

      return kong.response.exit(200, {
        filters = filters,
      })
    end
  },

  ["/routes/:routes/filters/disabled"] = {
    GET = function(self, db)
      local filters, err_t = get_filters(self, db)
      if err_t then
        return endpoints.handle_error(err_t)
      end

      for i = #filters, 1, -1 do
        if filters[i].enabled then
          table.remove(filters, i)
        end
      end

      return kong.response.exit(200, {
        filters = filters,
      })
    end
  },

}
