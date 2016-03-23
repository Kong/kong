return {
  fields = {
    header_name = {
      type = "string",
      default = "Kong-Request-ID"
    },
    generator = {
      type = "string",
      default = "uuid#counter",
      enum = {"uuid", "uuid#counter"}
    },
    echo_downstream = {
      type = "boolean",
      default = false
    }
  }
}
