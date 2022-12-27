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
    workspace_path = "%s" % ctx.path(Label("@//:WORKSPACE")).dirname
    content += '"WORKSPACE_PATH": "%s",\n' % workspace_path

    # Local env
    # Temporarily fix for https://github.com/bazelbuild/bazel/issues/14693#issuecomment-1079006291
    for key in [
        "PATH",
        "INSTALL_ROOT",
        "DOWNLOAD_ROOT",
        "LUAROCKS_DESTDIR",
        "OPENRESTY_DESTDIR",
        "OPENSSL_DESTDIR",
        "OPENRESTY_PREFIX",
        "OPENRESTY_RPATH",
        "OPENSSL_PREFIX",
        "LUAROCKS_PREFIX",
        "SSL_PROVIDER",
        "GITHUB_TOKEN",
        "RPM_SIGNING_KEY_FILE",
        "NFPM_RPM_PASSPHRASE",
    ]:
        value = ctx.os.environ.get(key, "")
        if value:
            content += '"%s": "%s",\n' % (key, value)

    # Kong Version
    kong_version = ctx.execute(["bash", "scripts/grep-kong-version.sh"], working_directory = workspace_path).stdout
    content += '"KONG_VERSION": "%s",' % kong_version.strip()

    ctx.file("BUILD.bazel", "")
    ctx.file("variables.bzl", "KONG_VAR = {\n" + content + "\n}")

def _load_bindings_impl(ctx):
    _load_vars(ctx)

load_bindings = repository_rule(
    implementation = _load_bindings_impl,
)
