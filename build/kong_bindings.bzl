"""
Global varibles
"""

def _load_vars(ctx):
    # Read env from .requirements
    requirements = ctx.read(Label("@kong//:.requirements"))
    content = ctx.execute(["bash", "-c", "echo '%s' | " % requirements +
                                         """grep -E '^(\\w*)=(.+)$' | sed -E 's/^(.*)=(.*)$/"\\1": "\\2",/'"""]).stdout
    content = content.replace('""', '"')

    # Workspace path
    content += '"WORKSPACE_PATH": "%s",' % ctx.path(Label("@//:WORKSPACE")).dirname

    # Local env
    # Temporarily fix for https://github.com/bazelbuild/bazel/issues/14693#issuecomment-1079006291
    for key in [
        "PATH",
        "INSTALL_PATH",
        "DOWNLOAD_ROOT",
        "LUAROCKS_DESTDIR",
        "OPENRESTY_DESTDIR",
        "OPENSSL_DESTDIR",
        "OPENRESTY_PREFIX",
        "OPENRESTY_RPATH",
        "OPENSSL_PREFIX",
        "LUAROCKS_PREFIX",
        "PACKAGE_TYPE",
        "SSL_PROVIDER",
        "GITHUB_TOKEN",
    ]:
        value = ctx.os.environ.get(key, "")
        if value:
            content += '"%s": "%s",' % (key, value)

    ctx.file("BUILD.bazel", "")
    ctx.file("variables.bzl", "KONG_VAR = {\n" + content + "\n}")

def _load_bindings_impl(ctx):
    _load_vars(ctx)

load_bindings = repository_rule(
    implementation = _load_bindings_impl,
)
