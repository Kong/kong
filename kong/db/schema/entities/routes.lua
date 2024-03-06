local typedefs = require("kong.db.schema.typedefs")
local deprecation = require("kong.deprecation")

local kong_router_flavor = kong and kong.configuration and kong.configuration.router_flavor

-- works with both `traditional_compatible` and `expressions` routes
local validate_route
if kong_router_flavor ~= "traditional" then
  local ipairs = ipairs
  local tonumber = tonumber
  local re_match = ngx.re.match

  local router = require("resty.router.router")
  local get_schema = require("kong.router.atc").schema
  local get_expression = kong_router_flavor == "traditional_compatible" and
                         require("kong.router.compat").get_expression or
                         require("kong.router.expressions").transform_expression

  local HTTP_PATH_SEGMENTS_PREFIX = "http.path.segments."
  local HTTP_PATH_SEGMENTS_SUFFIX_REG = [[^(0|[1-9]\d*)(_([1-9]\d*))?$]]

  validate_route = function(entity)
    local schema = get_schema(entity.protocols)
    local exp = get_expression(entity)

    local fields, err = router.validate(schema, exp)
    if not fields then
      return nil, "Router Expression failed validation: " .. err
    end

    for _, f in ipairs(fields) do
      if f:find(HTTP_PATH_SEGMENTS_PREFIX, 1, true) then
        local suffix = f:sub(#HTTP_PATH_SEGMENTS_PREFIX + 1)
        local m = re_match(suffix, HTTP_PATH_SEGMENTS_SUFFIX_REG, "jo")

        if (suffix ~= "len") and
           (not m or (m[2] and tonumber(m[1]) >= tonumber(m[3]))) then
          return nil, "Router Expression failed validation: " ..
                      "illformed http.path.segments.* field"
        end
      end -- if f:find
    end -- for fields

    return true
  end
end   -- if kong_router_flavor ~= "traditional"

if kong_router_flavor == "expressions" then
  return {
    name         = "routes",
    primary_key  = { "id" },
    endpoint_key = "name",
    workspaceable = true,

    fields = {
      { id             = typedefs.uuid, },
      { created_at     = typedefs.auto_timestamp_s },
      { updated_at     = typedefs.auto_timestamp_s },
      { name           = typedefs.utf8_name },
      { protocols      = { type     = "set",
                           description = "An array of the protocols this Route should allow.",
                           len_min  = 1,
                           required = true,
                           elements = typedefs.protocol,
                           mutually_exclusive_subsets = {
                             { "http", "https" },
                             { "tcp", "tls", "udp" },
                             { "tls_passthrough" },
                             { "grpc", "grpcs" },
                           },
                           default = { "http", "https" }, -- TODO: different default depending on service's scheme
                         }, },
      { https_redirect_status_code = { type = "integer",
                                       description = "The status code Kong responds with when all properties of a Route match except the protocol",
                                       one_of = { 426, 301, 302, 307, 308 },
                                       default = 426, required = true,
                                     }, },
      { strip_path     = { description = "When matching a Route via one of the paths, strip the matching prefix from the upstream request URL.", type = "boolean", required = true, default = true }, },
      { preserve_host  = { description = "When matching a Route via one of the hosts domain names, use the request Host header in the upstream request headers.", type = "boolean", required = true, default = false }, },
      { request_buffering  = { description = "Whether to enable request body buffering or not. With HTTP 1.1.", type = "boolean", required = true, default = true }, },
      { response_buffering  = { description = "Whether to enable response body buffering or not.", type = "boolean", required = true, default = true }, },
      { tags             = typedefs.tags },
      { service = { description = "The Service this Route is associated to. This is where the Route proxies traffic to.", type = "foreign", reference = "services" }, },
      { expression = { description = " The router expression.", type = "string", required = true }, },
      { priority = { description = "A number used to choose which route resolves a given request when several routes match it using regexes simultaneously.", type = "integer", required = true, default = 0 }, },
    },

    entity_checks = {
      { custom_entity_check = {
        field_sources = { "expression", "id", "protocols", },
        fn = validate_route,
      } },
    },
  }

-- router_flavor in ('traditional_compatible', 'traditional')
else
  local PATH_V1_DEPRECATION_MSG

  if kong_router_flavor == "traditional" then
    PATH_V1_DEPRECATION_MSG =
      "path_handling='v1' is deprecated and " ..
      "will be removed in future version, " ..
      "please use path_handling='v0' instead"

  elseif kong_router_flavor == "traditional_compatible" then
    PATH_V1_DEPRECATION_MSG =
      "path_handling='v1' is deprecated and " ..
      "will not work under 'traditional_compatible' router_flavor, " ..
      "please use path_handling='v0' instead"
  end

  local entity_checks = {
    { conditional = { if_field = "protocols",
                      if_match = { elements = { type = "string", not_one_of = { "grpcs", "https", "tls", "tls_passthrough" }}},
                      then_field = "snis",
                      then_match = { len_eq = 0 },
                      then_err = "'snis' can only be set when 'protocols' is 'grpcs', 'https', 'tls' or 'tls_passthrough'",
                    }},
    { custom_entity_check = {
      field_sources = { "path_handling" },
      fn = function(entity)
        if entity.path_handling == "v1" then
          deprecation(PATH_V1_DEPRECATION_MSG, { after = "3.0", })
        end

        return true
      end,
    }},
  }

  if kong_router_flavor == "traditional_compatible" then
    table.insert(entity_checks,
      { custom_entity_check = {
        run_with_missing_fields = true,
        fn = validate_route,
      }}
    )
  end

  return {
    name         = "routes",
    primary_key  = { "id" },
    endpoint_key = "name",
    workspaceable = true,
    subschema_key = "protocols",

    fields = {
      { id             = typedefs.uuid, },
      { created_at     = typedefs.auto_timestamp_s },
      { updated_at     = typedefs.auto_timestamp_s },
      { name           = typedefs.utf8_name },
      { protocols      = { type     = "set",
                           description = "An array of the protocols this Route should allow.",
                           len_min  = 1,
                           required = true,
                           elements = typedefs.protocol,
                           mutually_exclusive_subsets = {
                             { "http", "https" },
                             { "tcp", "tls", "udp" },
                             { "tls_passthrough" },
                             { "grpc", "grpcs" },
                           },
                           default = { "http", "https" }, -- TODO: different default depending on service's scheme
                         }, },
      { methods        = typedefs.methods },
      { hosts          = typedefs.hosts },
      { paths          = typedefs.router_paths },
      { headers = typedefs.headers {
        keys = typedefs.header_name {
          match_none = {
            {
              pattern = "^[Hh][Oo][Ss][Tt]$",
              err = "cannot contain 'host' header, which must be specified in the 'hosts' attribute",
            },
          },
        },
      } },
      { https_redirect_status_code = { type = "integer",
                                       description = "The status code Kong responds with when all properties of a Route match except the protocol",
                                       one_of = { 426, 301, 302, 307, 308 },
                                       default = 426, required = true,
                                     }, },
      { regex_priority = { description = "A number used to choose which route resolves a given request when several routes match it using regexes simultaneously.", type = "integer", default = 0 }, },
      { strip_path     = { description = "When matching a Route via one of the paths, strip the matching prefix from the upstream request URL.", type = "boolean", required = true, default = true }, },
      { path_handling  = { description = "Controls how the Service path, Route path and requested path are combined when sending a request to the upstream.", type = "string", default = "v0", one_of = { "v0", "v1" }, }, },
      { preserve_host  = { description = "When matching a Route via one of the hosts domain names, use the request Host header in the upstream request headers.", type = "boolean", required = true, default = false }, },
      { request_buffering  = { description = "Whether to enable request body buffering or not. With HTTP 1.1.", type = "boolean", required = true, default = true }, },
      { response_buffering  = { description = "Whether to enable response body buffering or not.", type = "boolean", required = true, default = true }, },
      { snis = { type = "set",
                 description = "A list of SNIs that match this Route when using stream routing.",
                 elements = typedefs.sni }, },
      { sources = typedefs.sources },
      { destinations = typedefs.destinations },
      { tags             = typedefs.tags },
      { service = { description = "The Service this Route is associated to. This is where the Route proxies traffic to.",
      type = "foreign", reference = "services" }, },
    },

    entity_checks = entity_checks,
  }
end
