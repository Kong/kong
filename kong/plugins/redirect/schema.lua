-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

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
