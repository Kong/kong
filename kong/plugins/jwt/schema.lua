return {
  fields = {
    uri_param_names = {type = "array", default = {"jwt"}},
    key_claim_names = {type = "array", required = true, default = {"key"}}
  }
}
