"""A module defining the third party dependency OpenResty"""

load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_archive")
load("@bazel_tools//tools/build_defs/repo:utils.bzl", "maybe")
load("@kong_bindings//:variables.bzl", "KONG_VAR")
load("//build:build_system.bzl", "git_or_local_repository")
load("//build/openresty/ada:ada_repositories.bzl", "ada_repositories")
load("//build/openresty/atc_router:atc_router_repositories.bzl", "atc_router_repositories")
load("//build/openresty/brotli:brotli_repositories.bzl", "brotli_repositories")
load("//build/openresty/openssl:openssl_repositories.bzl", "openssl_repositories")
load("//build/openresty/pcre:pcre_repositories.bzl", "pcre_repositories")
load("//build/openresty/simdjson_ffi:simdjson_ffi_repositories.bzl", "simdjson_ffi_repositories")
load("//build/openresty/snappy:snappy_repositories.bzl", "snappy_repositories")
load("//build/openresty/wasmx:wasmx_repositories.bzl", "wasmx_repositories")
load("//build/openresty/wasmx/filters:repositories.bzl", "wasm_filters_repositories")

# This is a dummy file to export the module's repository.
_NGINX_MODULE_DUMMY_FILE = """
filegroup(
    name = "all_srcs",
    srcs = glob(["**"]),
    visibility = ["//visibility:public"],
)

filegroup(
    name = "lualib_srcs",
    srcs = glob(["lualib/**/*.lua", "lib/**/*.lua"]),
    visibility = ["//visibility:public"],
)
"""

def openresty_repositories():
    pcre_repositories()
    openssl_repositories()
    simdjson_ffi_repositories()
    atc_router_repositories()
    wasmx_repositories()
    wasm_filters_repositories()
    brotli_repositories()
    snappy_repositories()
    ada_repositories()

    openresty_version = KONG_VAR["OPENRESTY"]

    maybe(
        openresty_http_archive_wrapper,
        name = "openresty",
        build_file = "//build/openresty:BUILD.openresty.bazel",
        sha256 = KONG_VAR["OPENRESTY_SHA256"],
        strip_prefix = "openresty-" + openresty_version,
        urls = [
            "https://openresty.org/download/openresty-" + openresty_version + ".tar.gz",
            "https://github.com/Kong/openresty-release-mirror/releases/download/" + openresty_version + "/openresty-" + openresty_version + ".tar.gz",
        ],
        patches = KONG_VAR["OPENRESTY_PATCHES"],
        patch_args = ["-p1"],
    )

    maybe(
        git_or_local_repository,
        name = "lua-kong-nginx-module",
        branch = KONG_VAR["LUA_KONG_NGINX_MODULE"],
        remote = "https://github.com/Kong/lua-kong-nginx-module",
        build_file_content = _NGINX_MODULE_DUMMY_FILE,
        recursive_init_submodules = True,
    )

    maybe(
        git_or_local_repository,
        name = "lua-resty-lmdb",
        branch = KONG_VAR["LUA_RESTY_LMDB"],
        remote = "https://github.com/Kong/lua-resty-lmdb",
        build_file_content = _NGINX_MODULE_DUMMY_FILE,
        recursive_init_submodules = True,
        patches = ["//build/openresty:lua-resty-lmdb-cross.patch"],
        patch_args = ["-p1", "-l"],  # -l: ignore whitespace
    )

    maybe(
        git_or_local_repository,
        name = "lua-resty-events",
        branch = KONG_VAR["LUA_RESTY_EVENTS"],
        remote = "https://github.com/Kong/lua-resty-events",
        build_file_content = _NGINX_MODULE_DUMMY_FILE,
        recursive_init_submodules = True,
    )

    maybe(
        git_or_local_repository,
        name = "ngx_brotli",
        branch = KONG_VAR["NGX_BROTLI"],
        remote = "https://github.com/google/ngx_brotli",
        build_file_content = _NGINX_MODULE_DUMMY_FILE,
        recursive_init_submodules = True,
    )

def _openresty_binding_impl(ctx):
    ctx.file("BUILD.bazel", "")
    ctx.file("WORKSPACE", "workspace(name = \"openresty_patch\")")

    version = "LuaJIT\\\\ 2.1.0-"
    for path in ctx.path("../openresty/bundle").readdir():
        if path.basename.startswith("LuaJIT-2.1-"):
            version = version + path.basename.replace("LuaJIT-2.1-", "")
            break

    ctx.file("variables.bzl", 'LUAJIT_VERSION = "%s"' % version)

openresty_binding = repository_rule(
    implementation = _openresty_binding_impl,
)

def openresty_http_archive_wrapper(name, **kwargs):
    http_archive(name = name, **kwargs)
    openresty_binding(name = name + "_binding")
