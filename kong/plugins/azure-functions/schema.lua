local typedefs = require "kong.db.schema.typedefs"

return {
  name = "azure-functions",
  fields = {
    { protocols = typedefs.protocols },
    { config = {
        type = "record",
        fields = {
          -- connection basics
          { timeout =  description = "Timeout in milliseconds before closing a connection to the Azure Functions server.",  type = "number",  default  = 600000, description = "Timeout in milliseconds before closing a connection to the Azure Functions server." }, },
          { keepalive =  description = "Time in milliseconds during which an idle connection to the Azure Functions server lives before being closed.",  type = "number",  default  = 60000, description = "Time in milliseconds during which an idle connection to the Azure Functions server lives before being closed." }, },
          { https =  description = "Use of HTTPS to connect with the Azure Functions server.",  type = "boolean", default  = true, description = "Use of HTTPS to connect with the Azure Functions server." }, },
          { https_verify =  description = "Set to `true` to authenticate the Azure Functions server.",  type = "boolean", default  = false, description = "Set to `true` to authenticate the Azure Functions server." }, },
          -- authorization
          { apikey =  description = "The apikey to access the Azure resources. If provided, it is injected as the `x-functions-key` header.",  type = "string", encrypted = true, referenceable = true, description = "The apikey to access the Azure resources. If provided, it is injected as the `x-functions-key` header." }, }, -- encrypted = true is a Kong Enterprise Exclusive feature. It does nothing in Kong CE
          { clientid =  description = "The `clientid` to access the Azure resources. If provided, it is injected as the `x-functions-clientid` header.",  type = "string", encrypted = true, referenceable = true, description = "The `clientid` to access the Azure resources. If provided, it is injected as the `x-functions-clientid` header." }, }, -- encrypted = true is a Kong Enterprise Exclusive feature. It does nothing in Kong CE
          -- target/location
          { appname =  description = "The Azure app name.",  type = "string",  required = true, description = "The Azure app name." }, },
          { hostdomain =  description = "The domain where the function resides.",  type = "string",  required = true, default = "azurewebsites.net", description = "The domain where the function resides." }, },
          { routeprefix =  description = "Route prefix to use.",  type = "string",  default = "api", description = "Route prefix to use." }, },
          { functionname =  description = "Name of the Azure function to invoke.",  type = "string",  required = true, description = "Name of the Azure function to invoke." }, },
        },
    }, },
  },
}
