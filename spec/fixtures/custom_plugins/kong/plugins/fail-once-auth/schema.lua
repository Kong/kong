return {
  name = "fail-once-auth",
  fields = {
    { config = {
        type = "record",
        fields = {
          { message = { type = "string", default = "try again!" }, },
        },
    }, },
  }
}
