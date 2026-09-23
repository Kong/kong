return {
  name = "reference-ca-cert",
  fields = {
    {
      config = {
        type = "record",
        fields = {
          { pre_key = { type = "string", }, },
          { ca_certificates = { type = "array", required = true, elements = { type = "string", uuid = true, }, }, },
          { post_key = { type = "string", }, },
        },
      },
    },
  },
}
