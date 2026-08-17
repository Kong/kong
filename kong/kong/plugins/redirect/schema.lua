local typedefs = require "kong.db.schema.typedefs"

return {
    name = "redirect",
    fields = {
        {
            protocols = typedefs.protocols_http
        },
        {
            config = {
                type = "record",
                fields = {
                    {
                        status_code = {
                            description = "The response code to send. Must be an integer between 100 and 599.",
                            type = "integer",
                            required = true,
                            default = 301,
                            between = { 100, 599 }
                        }
                    },
                    {
                        location = typedefs.url {
                            description = "The URL to redirect to",
                            required = true
                        }
                    },
                    {
                        keep_incoming_path = {
                            description = "Use the incoming request's path and query string in the redirect URL",
                            type = "boolean",
                            default = false
                        }
                    }
                }
            }
        }
    }
}
