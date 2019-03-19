std             = "ngx_lua"
unused_args     = false
redefined       = false
max_line_length = false


globals = {
    "_KONG",
    "ngx.IS_CLI",
}


not_globals = {
    "string.len",
    "table.getn",
}


files["spec/**/*.lua"] = {
    std = "ngx_lua+busted",
}
