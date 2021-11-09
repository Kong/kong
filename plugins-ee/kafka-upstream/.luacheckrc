unused_args     = false
redefined       = false
max_line_length = false

std = "ngx_lua"
globals = {
	"kong",
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
    "kong-pongo/",
}


files["spec/**/*.lua"] = {
    std = "ngx_lua+busted",
}