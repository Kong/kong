load("//build/openresty/wasmx:wasmx_repositories.bzl", "wasm_runtimes")

wasmx_configure_options = select({
    "@kong//:wasmx_el7_workaround_flag": [
        # bypass "multiple definitions of 'assertions'" linker error from wasm.h:
        # https://github.com/WebAssembly/wasm-c-api/blob/master/include/wasm.h#L29
        # and ensure a more recent libstdc++ is found
        # https://github.com/Kong/ngx_wasm_module/blob/main/assets/release/Dockerfiles/Dockerfile.amd64.centos7#L28-L31
        "--with-ld-opt=\"-Wl,--allow-multiple-definition -L/opt/rh/devtoolset-8/root/usr/lib/gcc/x86_64-redhat-linux/8\"",
    ],
    "//conditions:default": [],
}) + select({
    "@kong//:wasmx_flag": [
        "--with-cc-opt=\"-DNGX_WASM_HOST_PROPERTY_NAMESPACE=kong\"",
    ],
    "//conditions:default": [],
}) + select({
    "@kong//:wasmx_static_mod": [
        "--add-module=$$EXT_BUILD_ROOT$$/external/ngx_wasm_module",
    ],
    "@kong//:wasmx_dynamic_mod": [
        "--with-compat",
        "--add-dynamic-module=$$EXT_BUILD_ROOT$$/external/ngx_wasm_module",
    ],
    "//conditions:default": [],
})

wasmx_env = select({
    "@kong//build/openresty/wasmx:use_v8": {
        "NGX_WASM_RUNTIME": "v8",
        # see the above comments and source for this dummy ar script
        "AR": "$(execpath @kong//build/openresty:wasmx/wasmx_v8_ar)",
    },
    "@kong//build/openresty/wasmx:use_wasmer": {
        "NGX_WASM_RUNTIME": "wasmer",
    },
    "@kong//build/openresty/wasmx:use_wasmtime": {
        "NGX_WASM_RUNTIME": "wasmtime",
    },
    "//conditions:default": {},
}) | select({
    "@kong//:wasmx_flag": {
        "NGX_WASM_RUNTIME_LIB": "$$INSTALLDIR/../wasm_runtime/lib",
        "NGX_WASM_RUNTIME_INC": "$$INSTALLDIR/../wasm_runtime/include",
    },
    "//conditions:default": {},
})

def _wasm_runtime_link_impl(ctx):
    symlinks = []
    for file in ctx.files.runtime:
        # strip ../REPO_NAME/ from the path
        path = "/".join(file.short_path.split("/")[2:])
        symlink = ctx.actions.declare_file(ctx.attr.prefix + "/" + path)
        symlinks.append(symlink)
        ctx.actions.symlink(output = symlink, target_file = file)

    return [DefaultInfo(files = depset(symlinks))]

_wasm_runtime_link = rule(
    implementation = _wasm_runtime_link_impl,
    attrs = {
        "prefix": attr.string(),
        "runtime": attr.label(),
    },
)

def wasm_runtime(**kwargs):
    select_conds = {}
    for runtime in wasm_runtimes:
        for os in wasm_runtimes[runtime]:
            for arch in wasm_runtimes[runtime][os]:
                select_conds["@wasmx_config_settings//:use_%s_%s_%s" % (runtime, os, arch)] = \
                    "@%s-%s-%s//:all_srcs" % (runtime, os, arch)

    _wasm_runtime_link(
        prefix = kwargs["name"],
        runtime = select(select_conds),
        **kwargs
    )
