"""Definie utils for luarocks build"""

load("@kong_bindings//:variables.bzl", "KONG_VAR")

def _check_string_not_empty_impl(ctx):
    if not ctx.attr.value:
        fail(ctx.attr.error_message)

check_string_not_empty = rule(
    implementation = _check_string_not_empty_impl,
    attrs = {
        "value": attr.string(),
        "error_message": attr.string(mandatory = True),
    },
)

_private_rocks_url = "https://dummy:%s@raw.githubusercontent.com/Kong/kongrocks/main/rocks" % KONG_VAR.get("GITHUB_TOKEN")

# This variable contains a list of custom flags that need to be set if our
# private luarocks server is to be used. This was added in the context of NIST SLSA
# requirements
luarocks_servers_flags = select({
    "@kong//:private_luarocks_flag": " --only-sources='" + _private_rocks_url + "' --only-server='" + _private_rocks_url + "' ",
    "//conditions:default": "",
})
