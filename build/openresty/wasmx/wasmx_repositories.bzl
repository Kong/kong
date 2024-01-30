"""A module defining the third party dependency WasmX"""

load("@bazel_tools//tools/build_defs/repo:git.bzl", "new_git_repository")
load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_archive")
load("@kong_bindings//:variables.bzl", "KONG_VAR")

wasm_runtime_build_file = """
filegroup(
    name = "all_srcs",
    # note: we do static link only for runtimes
    srcs = glob(["include/**", "lib/*.a"]),
    visibility = ["//visibility:public"]
)

filegroup(
    name = "lib",
    srcs = glob(["**/*.so", "**/*.dylib"]),
    visibility = ["//visibility:public"]
)
"""

wasm_runtimes = {
    "wasmer": {
        "linux": {
            "x86_64": "3db46d2974b2c91aba2f0311dc26f59c1def473591768cddee8cdbf4783bf2c4",
            "aarch64": "c212eebdf1cc6bf71e7b56d7421eb3494c3a6ab1faf50a55150b7522183d1d36",
        },
        "macos": {
            "x86_64": "008610ddefdd3e04af9733969da616f9a344017db451476a1ee1cf6702895f02",
            "aarch64": "8534b278c1006ccc7f128bd1611636e12a33b9e625344331f9be3b56a5bb3286",
        },
    },
    "v8": {
        "linux": {
            "x86_64": "41309c43d0f06334c8cf553b34973c42cfbdc3aadc1ca374723d4b6de48992d9",
            "aarch64": "4e8b3881762b31078299ff1be2d48280c32ab4e1d48a0ce9ec267c4e302bb9ea",
        },
        "macos": {
            "x86_64": "862260d74f39a96aac556f821c28beb4def5ad5d1e5c70a0aa80d1af7d581f8b",
            # "aarch64": None, no aarch64 v8 runtime release yet
        },
    },
    "wasmtime": {
        "linux": {
            "x86_64": "a1285b0e2e3c6edf9cb6c7f214a682780f01ca8746a5d03f162512169cdf1e50",
            "aarch64": "ef527ed31c3f141b5949bfd2e766a908f44b66ee839d4f0f22e740186236fd48",
        },
        "macos": {
            "x86_64": "c30ffb79f8097512fbe9ad02503dcdb0cd168eec2112b6951a013eed51050245",
            "aarch64": "2834d667fc218925184db77fa91eca44d14f688a4972e2f365fe2b7c12e6d49f",
        },
    },
}

def wasmx_repositories():
    wasm_module_branch = KONG_VAR["NGX_WASM_MODULE_BRANCH"]
    if wasm_module_branch == "":
        wasm_module_branch = KONG_VAR["NGX_WASM_MODULE"]

    new_git_repository(
        name = "ngx_wasm_module",
        branch = wasm_module_branch,
        remote = KONG_VAR["NGX_WASM_MODULE_REMOTE"],
        build_file_content = """
filegroup(
    name = "all_srcs",
    srcs = glob(["src/**"]),
    visibility = ["//visibility:public"]
)

filegroup(
    name = "lua_libs",
    srcs = glob(["lib/resty/**"]),
    visibility = ["//visibility:public"]
)

filegroup(
    name = "v8bridge_srcs",
    srcs = glob(["lib/v8bridge/**"]),
    visibility = ["//visibility:public"]
)
""",
    )

    wasmtime_version = KONG_VAR["WASMTIME"]
    wasmer_version = KONG_VAR["WASMER"]
    v8_version = KONG_VAR["V8"]

    for os in wasm_runtimes["v8"]:
        for arch in wasm_runtimes["v8"][os]:
            # normalize macos to darwin used in url
            url_os = os
            if os == "macos":
                url_os = "darwin"
            url_arch = arch
            if arch == "aarch64":
                url_arch = "arm64"

            http_archive(
                name = "v8-%s-%s" % (os, arch),
                urls = [
                    "https://github.com/Kong/ngx_wasm_runtimes/releases/download/v8-" +
                    v8_version + "/ngx_wasm_runtime-v8-%s-%s-%s.tar.gz" % (v8_version, url_os, url_arch),
                ],
                sha256 = wasm_runtimes["v8"][os][arch],
                strip_prefix = "v8-%s-%s-%s" % (v8_version, url_os, url_arch),
                build_file_content = wasm_runtime_build_file,
            )

    for os in wasm_runtimes["wasmer"]:
        for arch in wasm_runtimes["wasmer"][os]:
            # normalize macos to darwin used in url
            url_os = os
            if os == "macos":
                url_os = "darwin"
            url_arch = arch
            if arch == "aarch64" and os == "macos":
                url_arch = "arm64"

            http_archive(
                name = "wasmer-%s-%s" % (os, arch),
                urls = [
                    "https://github.com/wasmerio/wasmer/releases/download/v" +
                    wasmer_version + "/wasmer-%s-%s.tar.gz" % (url_os, url_arch),
                ],
                sha256 = wasm_runtimes["wasmer"][os][arch],
                strip_prefix = "wasmer-%s-%s" % (url_os, url_arch),
                build_file_content = wasm_runtime_build_file,
            )

    for os in wasm_runtimes["wasmtime"]:
        for arch in wasm_runtimes["wasmtime"][os]:
            http_archive(
                name = "wasmtime-%s-%s" % (os, arch),
                urls = [
                    "https://github.com/bytecodealliance/wasmtime/releases/download/v" +
                    wasmtime_version + "/wasmtime-v%s-%s-%s-c-api.tar.xz" % (wasmtime_version, arch, os),
                ],
                strip_prefix = "wasmtime-v%s-%s-%s-c-api" % (wasmtime_version, arch, os),
                sha256 = wasm_runtimes["wasmtime"][os][arch],
                build_file_content = wasm_runtime_build_file,
            )

    wasmx_config_settings(name = "wasmx_config_settings")

# generate boilerplate config_settings
def _wasmx_config_settings_impl(ctx):
    content = ""
    for runtime in wasm_runtimes:
        for os in wasm_runtimes[runtime]:
            for arch in wasm_runtimes[runtime][os]:
                content += ("""
config_setting(
    name = "use_{runtime}_{os}_{arch}",
    constraint_values = [
        "@platforms//cpu:{arch}",
        "@platforms//os:{os}",
    ],
    flag_values = {{
        "@kong//:wasmx": "true",
        "@kong//:wasm_runtime": "{runtime}",
    }},
    visibility = ["//visibility:public"],
)
            """.format(
                    os = os,
                    arch = arch,
                    runtime = runtime,
                ))

        ctx.file("BUILD.bazel", content)

wasmx_config_settings = repository_rule(
    implementation = _wasmx_config_settings_impl,
)
