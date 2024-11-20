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
                        -- This is intentionally flexible and does not require a http/https prefix in order to support
                        -- redirecting to uris such as someapp://path
                        location = {
                            description = "The URL to redirect to",
                            type = "string",
                            required = true
                        }
                    },
                    {
                        incoming_path = {
                            description =
                            "What to do with the incoming path. 'ignore' will use the path from the 'location' field, 'keep' will keep the incoming path, 'merge' will merge the incoming path with the location path, choosing the location query parameters over the incoming one.",
                            type = "string",
                            default = "ignore",
                            one_of = { "ignore", "keep", "merge" }
                        }
                    }
                }
            }
        }
    }
}
