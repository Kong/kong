return {
  no_consumer = true,
  fields = {
    uri_param_names = {type = "array", default = {"jwt"}},
    claims_to_verify = {type = "array", enum = {"exp", "nbf"}}
  }
}
