return {
    name = "upstream-service-signature",
    fields = {
        { config = {
            type = "record",
            fields = {
                { signature_key = { type = "string",required = true } },
                { signature_secret = { type = "string",required = true } }
            }
        }
        }
    }
}