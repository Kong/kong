return {
  {
    name               = "ratelimiting_metrics",
    primary_key        = { "identifier", "period", "period_date", "service_id", "route_id" },
    generate_admin_api = false,
    ttl                = true,
    db_export          = false,
    fields             = {
      {
        identifier = {
          type     = "string",
          required = true,
          len_min  = 0,
        },
      },
      {
        period     = {
          type     = "string",
          required = true,
        },
      },
      {
        period_date = {
          type      = "integer",
          timestamp = true,
          required  = true,
        },
      },
      {
        service_id = { -- don't make this `foreign`
          type     = "string",
          uuid     = true,
          required = true,
        },
      },
      {
        route_id = { -- don't make this `foreign`
          type     = "string",
          uuid     = true,
          required = true,
        },
      },
      {
        value = {
          type     = "integer",
          required = true,
        },
      },
    },
  },
}
