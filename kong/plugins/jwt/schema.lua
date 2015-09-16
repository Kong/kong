return {
  fields = {
    uri_param_names = {type = "array", default = {"jwt"}},
    key_claim_names = {required = true, type = "array", default = {"token"}}
  }
}
