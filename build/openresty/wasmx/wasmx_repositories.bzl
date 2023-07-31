"""A module defining the third party dependency WasmX"""

load("@bazel_tools//tools/build_defs/repo:git.bzl", "new_git_repository")
load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_archive")
load("@bazel_tools//tools/build_defs/repo:utils.bzl", "maybe")
load("@kong_bindings//:variables.bzl", "KONG_VAR")

def wasmx_repositories():
    wasmtime_version = KONG_VAR["WASMTIME"]
    wasmer_version = KONG_VAR["WASMER"]
    v8_version = KONG_VAR["V8"]
    wasmtime_os = KONG_VAR["WASMTIME_OS"]
    wasmer_os = KONG_VAR["WASMER_OS"]
    v8_os = KONG_VAR["V8_OS"]

    ngx_wasm_module_tag = KONG_VAR["NGX_WASM_MODULE"]
    ngx_wasm_module_branch = KONG_VAR.get("NGX_WASM_MODULE_BRANCH")
    if ngx_wasm_module_branch:
        ngx_wasm_module_tag = None

    maybe(
        new_git_repository,
        name = "ngx_wasm_module",
        branch = ngx_wasm_module_branch,
        tag = ngx_wasm_module_tag,
        remote = KONG_VAR.get("NGX_WASM_MODULE_REMOTE", "https://github.com/Kong/ngx_wasm_module.git"),
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

    maybe(
        http_archive,
        name = "v8-x86_64",
        urls = [
            "https://github.com/Kong/ngx_wasm_runtimes/releases/download/v8-" +
            v8_version + "/ngx_wasm_runtime-v8-" + v8_version + "-" + v8_os + "-x86_64.tar.gz",
        ],
        strip_prefix = "v8-" + v8_version + "-" + v8_os + "-x86_64",
        build_file_content = """
filegroup(
    name = "all_srcs",
    srcs = glob(["include/**", "lib/**"]),
    visibility = ["//visibility:public"]
)

filegroup(
    name = "lib",
    srcs = glob(["**/*.a"]),
    visibility = ["//visibility:public"]
)
""",
    )

    maybe(
        http_archive,
        name = "v8-aarch64",
        urls = [
            "https://github.com/Kong/ngx_wasm_runtimes/releases/download/v8-" +
            v8_version + "/ngx_wasm_runtime-v8-" + v8_version + "-" + v8_os + "-aarch64.tar.gz",
        ],
        strip_prefix = "v8-" + v8_version + "-" + v8_os + "-aarch64",
        build_file_content = """
filegroup(
    name = "all_srcs",
    srcs = glob(["include/**", "lib/**"]),
    visibility = ["//visibility:public"]
)

filegroup(
    name = "lib",
    srcs = glob(["**/*.a"]),
    visibility = ["//visibility:public"]
)
""",
    )

    maybe(
        http_archive,
        name = "wasmer-x86_64",
        urls = [
            "https://github.com/wasmerio/wasmer/releases/download/v" +
            wasmer_version + "/wasmer-" + wasmer_os + "-x86_64.tar.gz",
        ],
        build_file_content = """
filegroup(
    name = "all_srcs",
    srcs = glob(["include/**", "lib/**"]),
    visibility = ["//visibility:public"]
)

filegroup(
    name = "lib",
    srcs = glob(["**/*.so", "**/*.dylib"]),
    visibility = ["//visibility:public"]
)
""",
    )

    maybe(
        http_archive,
        name = "wasmer-aarch64",
        urls = [
            "https://github.com/wasmerio/wasmer/releases/download/v" +
            wasmer_version + "/wasmer-" + wasmer_os + "-aarch64.tar.gz",
        ],
        build_file_content = """
filegroup(
    name = "all_srcs",
    srcs = glob(["include/**", "lib/**"]),
    visibility = ["//visibility:public"]
)

filegroup(
    name = "lib",
    srcs = glob(["**/*.so", "**/*.dylib"]),
    visibility = ["//visibility:public"]
)
""",
    )

    maybe(
        http_archive,
        name = "wasmtime-x86_64",
        urls = [
            "https://github.com/bytecodealliance/wasmtime/releases/download/v" +
            wasmtime_version + "/wasmtime-v" + wasmtime_version + "-x86_64-" + wasmtime_os + "-c-api.tar.xz",
        ],
        strip_prefix = "wasmtime-v" + wasmtime_version + "-x86_64-" + wasmtime_os + "-c-api",
        build_file_content = """
filegroup(
    name = "all_srcs",
    srcs = glob(["include/**", "lib/**"]),
    visibility = ["//visibility:public"]
)

filegroup(
    name = "lib",
    srcs = glob(["**/*.so", "**/*.dylib"]),
    visibility = ["//visibility:public"]
)
""",
    )

    maybe(
        http_archive,
        name = "wasmtime-aarch64",
        urls = [
            "https://github.com/bytecodealliance/wasmtime/releases/download/v" +
            wasmtime_version + "/wasmtime-v" + wasmtime_version + "-aarch64-" + wasmtime_os + "-c-api.tar.xz",
        ],
        strip_prefix = "wasmtime-v" + wasmtime_version + "-aarch64-" + wasmtime_os + "-c-api",
        build_file_content = """
filegroup(
    name = "all_srcs",
    srcs = glob(["include/**", "lib/**"]),
    visibility = ["//visibility:public"]
)

filegroup(
    name = "lib",
    srcs = glob(["**/*.so", "**/*.dylib"]),
    visibility = ["//visibility:public"]
)
""",
    )
