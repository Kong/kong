return {
  name = "azure-functions",
  fields = {
    { config = {
        type = "record",
        fields = {
          -- connection basics
          { timeout       = { type = "number",  default  = 600000}, },
          { keepalive     = { type = "number",  default  = 60000 }, },
          { https         = { type = "boolean", default  = true  }, },
          { https_verify  = { type = "boolean", default  = false }, },
          -- authorization
          { apikey        = { type = "string"                    }, },
          { clientid      = { type = "string"                    }, },
          -- target/location
          { appname       = { type = "string",  required = true  }, },
          { hostdomain    = { type = "string",  required = true, default = "azurewebsites.net" }, },
          { routeprefix   = { type = "string",  default = "api"  }, },
          { functionname  = { type = "string",  required = true  }, },
        },
    }, },
  },
}
