return {
  no_consumer = true,
  fields = {
    uri_param_names = {type = "array", default = {"jwt"}},
    secret_key_field = {type = "string", default = "iss"},
    claims_to_verify = {type = "array", enum = {"exp", "nbf"}}
  }
}
