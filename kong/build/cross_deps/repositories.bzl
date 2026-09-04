load("//build/cross_deps/libxcrypt:repositories.bzl", "libxcrypt_repositories")
load("//build/cross_deps/libyaml:repositories.bzl", "libyaml_repositories")
load("//build/cross_deps/zlib:repositories.bzl", "zlib_repositories")

def cross_deps_repositories():
    zlib_repositories()
    libyaml_repositories()
    libxcrypt_repositories()
