std = "ngx_lua"
max_line_length = false

globals = {
    "_KONG",
    "kong",
    "ngx.IS_CLI",
}

not_globals = {
    "string.len",
    "table.getn",
}

files["spec/**/*.lua"] = {
    std = "ngx_lua+busted",
}
