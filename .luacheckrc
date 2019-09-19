unused_args     = false
redefined       = false
max_line_length = false

std = "ngx_lua"
files["spec"] = {
	std = "+busted";
}
globals = {
	"kong",
}

