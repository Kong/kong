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


ignore = {
    "6.", -- ignore whitespace warnings
}


exclude_files = {
    "spec/fixtures/invalid-module.lua",
    "spec-old-api/fixtures/invalid-module.lua",
}


files["kong/plugins/ldap-auth/*.lua"] = {
    read_globals = {
        "bit.mod",
        "string.pack",
        "string.unpack",
    },
}


files["spec/**/*.lua"] = {
    std = "ngx_lua+busted",
}

files["spec-old-api/**/*.lua"] = {
    std = "ngx_lua+busted",
}
