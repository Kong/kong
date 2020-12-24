std             = "ngx_lua"
unused_args     = false
redefined       = false
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


ignore = {
    "6.", -- ignore whitespace warnings
}


exclude_files = {
    "spec/fixtures/invalid-module.lua",
    "spec-old-api/fixtures/invalid-module.lua",
}


files["kong/hooks.lua"] = {
    read_globals = {
        "table.pack",
        "table.unpack",
    }
}


files["kong/plugins/ldap-auth*/*.lua"] = {
    read_globals = {
        "bit.mod",
        "string.pack",
        "string.unpack",
    },
}


files["kong/tracing/init.lua"] = {
    read_globals = {
        "table.pack",
        "table.unpack",
    }
}


files["spec/**/*.lua"] = {
    std = "ngx_lua+busted",
}

files["spec-old-api/**/*.lua"] = {
    std = "ngx_lua+busted",
}

files["spec-ee/**/*.lua"] = {
    std = "ngx_lua+busted",
}

files["kong/keyring/init.lua"] = {
    read_globals = {
        "table.pack",
        "table.unpack",
    }
}


files["kong/hooks.lua"] = {
    read_globals = {
        "table.pack",
        "table.unpack",
    }
}


files["spec-ee/01-unit/07-keyring/01-init_spec.lua"] = {
    read_globals = {
        "table.pack",
    }
}

files["kong/tools/sandbox.lua"] = {
    read_globals = {
        "table.pack",
        "table.unpack",
        string = { fields = {rep = { read_only = false } } },
    }
}

files["kong/tools/sandbox_helpers.lua"] = {
    read_globals = {
        "table.unpack",
    }
}

files["spec/01-unit/020-sandbox/02-sandbox_helpers_spec.lua"] = {
    read_globals = {
        "table.unpack",
    }
}
