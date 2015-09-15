return {
  fields = {
    uri_param_names = {type = "array", default = {"jwt"}},
    username_claims = {required = true, type = "array", default = {"username"}}
  }
}
