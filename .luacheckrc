redefined = false
unused_args = false
globals = {"ngx", "dao", "app", "configuration"}

files["kong/vendor/lapp.lua"] = {
   ignore = {"lapp", "typespec"}
}

files["kong/api/app.lua"] = {
   globals = {"jit"}
}

files["spec/"] = {
   globals = {"describe", "it", "before_each", "setup", "after_each", "teardown", "stub", "mock", "spy", "finally"}
}
