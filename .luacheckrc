redefined = false
unused_args = false
globals = {"ngx", "dao", "app", "configuration"}

files["kong/"] = {
  std = "luajit"
}

files["kong/vendor/lapp.lua"] = {
   ignore = {"lapp", "typespec"}
}

files["kong/vendor/ssl.lua"] = {
   ignore = {"FFI_DECLINED"}
}

files["kong/vendor/resty_http.lua"] = {
  global = false,
  unused = false
}

files["spec/"] = {
  globals = {"describe", "it", "before_each", "setup", "after_each", "teardown", "stub", "mock", "spy", "finally", "pending"}
}
