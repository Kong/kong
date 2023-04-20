
from globmatch import glob_match

from main import FileInfo

def transform(f: FileInfo):
    # XXX: libxslt uses libtool and it injects some extra rpaths
    # we only care about the kong library rpath so removing it here
    # until we find a way to remove the extra rpaths from it
    # It should have no side effect as the extra rpaths are long random
    # paths created by bazel.

    if glob_match(f.path, ["**/kong/lib/libxslt.so*", "**/kong/lib/libexslt.so*", "**/kong/lib/libjq.so*"]):
        if f.rpath and "/usr/local/kong/lib" in f.rpath:
            f.rpath = "/usr/local/kong/lib"
        elif f.runpath and "/usr/local/kong/lib" in f.runpath:
            f.runpath = "/usr/local/kong/lib"
        # otherwise remain unmodified

    # XXX: boringssl also hardcodes the rpath during build; normally library
    # loads libssl.so also loads libcrypto.so so we _should_ be fine.
    # we are also replacing boringssl with openssl 3.0 for FIPS for not fixing this for now
    if glob_match(f.path, ["**/kong/lib/libssl.so.1.1"]):
        if f.runpath and "boringssl_fips/build/crypto" in f.runpath:
            f.runpath = "<removed in manifest>"
        elif f.rpath and "boringssl_fips/build/crypto" in f.rpath:
            f.rpath = "<removed in manifest>"

