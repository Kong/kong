-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

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
          { apikey        = { type = "string", encrypted = true, referenceable = true }, }, -- encrypted = true is a Kong Enterprise Exclusive feature. It does nothing in Kong CE
          { clientid      = { type = "string", encrypted = true, referenceable = true }, }, -- encrypted = true is a Kong Enterprise Exclusive feature. It does nothing in Kong CE
          -- target/location
          { appname       = { type = "string",  required = true  }, },
          { hostdomain    = { type = "string",  required = true, default = "azurewebsites.net" }, },
          { routeprefix   = { type = "string",  default = "api"  }, },
          { functionname  = { type = "string",  required = true  }, },
        },
    }, },
  },
}
