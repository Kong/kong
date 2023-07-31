import os
import re

def read_requirements(path=None):
    if not path:
        path = os.path.join(os.path.dirname(__file__), "..", "..", ".requirements")

    with open(path, "r") as f:
        lines = [re.findall("(.+)=([^# ]+)", d) for d in f.readlines()]
        return {l[0][0]: l[0][1].strip() for l in lines if l}

def common_suites(expect, fips: bool = False, libxcrypt_no_obsolete_api: bool = False):
    # file existence
    expect("/usr/local/kong/include/google/protobuf/**.proto",
           "includes Google protobuf headers").exists()

    expect("/usr/local/kong/include/kong/**/*.proto",
           "includes Kong protobuf headers").exists()

    expect("/etc/kong/kong.logrotate", "includes logrotate config").exists()

    # binary correctness
    expect("/usr/local/openresty/nginx/sbin/nginx", "nginx rpath should contain kong lib") \
        .rpath.equals("/usr/local/openresty/luajit/lib:/usr/local/kong/lib")

    expect("/usr/local/openresty/nginx/sbin/nginx", "nginx binary should contain dwarf info for dynatrace") \
        .has_dwarf_info.equals(True) \
        .has_ngx_http_request_t_DW.equals(True)

    expect("/usr/local/openresty/nginx/sbin/nginx", "nginx binary should link pcre statically") \
        .exported_symbols.contain("pcre_free") \
        .needed_libraries.do_not().contain_match("libpcre.so.+")

    expect("/usr/local/openresty/nginx/sbin/nginx", "nginx should not be compiled with debug flag") \
        .nginx_compile_flags.do_not().match("with\-debug")

    expect("/usr/local/openresty/nginx/sbin/nginx", "nginx should include Kong's patches") \
        .functions \
        .contain("ngx_http_lua_kong_ffi_set_grpc_authority") \
        .contain("ngx_http_lua_ffi_balancer_enable_keepalive") \
        .contain("ngx_http_lua_kong_ffi_set_dynamic_log_level") \
        .contain("ngx_http_lua_kong_ffi_get_dynamic_log_level") \
        .contain("ngx_http_lua_kong_ffi_get_static_tag") \
        .contain("ngx_stream_lua_kong_ffi_get_static_tag") \
        .contain("ngx_http_lua_kong_ffi_get_full_client_certificate_chain") \
        .contain("ngx_http_lua_kong_ffi_disable_session_reuse") \
        .contain("ngx_http_lua_kong_ffi_set_upstream_client_cert_and_key") \
        .contain("ngx_http_lua_kong_ffi_set_upstream_ssl_trusted_store") \
        .contain("ngx_http_lua_kong_ffi_set_upstream_ssl_verify") \
        .contain("ngx_http_lua_kong_ffi_set_upstream_ssl_verify_depth") \
        .contain("ngx_stream_lua_kong_ffi_get_full_client_certificate_chain") \
        .contain("ngx_stream_lua_kong_ffi_disable_session_reuse") \
        .contain("ngx_stream_lua_kong_ffi_set_upstream_client_cert_and_key") \
        .contain("ngx_stream_lua_kong_ffi_set_upstream_ssl_trusted_store") \
        .contain("ngx_stream_lua_kong_ffi_set_upstream_ssl_verify") \
        .contain("ngx_stream_lua_kong_ffi_set_upstream_ssl_verify_depth") \
        .contain("ngx_http_lua_kong_ffi_var_get_by_index") \
        .contain("ngx_http_lua_kong_ffi_var_set_by_index") \
        .contain("ngx_http_lua_kong_ffi_var_load_indexes")

    if libxcrypt_no_obsolete_api:
        expect("/usr/local/openresty/nginx/sbin/nginx", "nginx linked with libxcrypt.so.2") \
            .needed_libraries.contain("libcrypt.so.2")
    else:
        expect("/usr/local/openresty/nginx/sbin/nginx", "nginx should link libxcrypt.so.1") \
            .needed_libraries.contain("libcrypt.so.1")

    if not fips:
        expect("/usr/local/openresty/nginx/sbin/nginx", "nginx compiled with OpenSSL 3.1.x") \
            .nginx_compiled_openssl.matches("OpenSSL 3.1.\d") \
            .version_requirement.key("libssl.so.3").less_than("OPENSSL_3.2.0") \
            .version_requirement.key("libcrypto.so.3").less_than("OPENSSL_3.2.0") \

        expect("**/*.so", "dynamic libraries are compiled with OpenSSL 3.1.x") \
            .version_requirement.key("libssl.so.3").less_than("OPENSSL_3.2.0") \
            .version_requirement.key("libcrypto.so.3").less_than("OPENSSL_3.2.0") \


def ee_suites(expect, fips: bool = False):
    # file existence
    expect("/usr/local/kong/COPYRIGHT", "includes Kong COPYRIGHT file").exists()

    expect("/etc/logrotate.d/kong-enterprise-edition", "includes Kong EE logrotate config")\
        .exists().link.equals("/etc/kong/kong.logrotate")

    expect("/lib/systemd/system/kong-enterprise-edition.service", "includes Kong EE systemd file")\
        .exists()

    # binary correctness

    # LuaJIT profiling patch
    expect("/usr/local/openresty/luajit/lib/libluajit-5.1.so*",
           "LuaJIT should include Kong profiling extension patch") \
        .functions \
        .contain("luaopen_kprof")

    ZLIB_VERSION = "1.2.13"
    expect("**/*.so", "zlib version is less than %s" % ZLIB_VERSION) \
        .version_requirement.key("libz.so.1").is_not().greater_than("ZLIB_%s" % ZLIB_VERSION)

    LIBXML2_VERSION = read_requirements()["LIBXML2"]
    expect("**/*.so", "libxml2 version is less than %s" % LIBXML2_VERSION) \
        .version_requirement.key("libxml2.so.2").is_not().greater_than("LIBXML2_%s" % LIBXML2_VERSION) \
        .version_requirement.key("libxslt.so.1").is_not().greater_than("LIBXML2_%s" % LIBXML2_VERSION)

    if fips:
        expect("/usr/local/kong/lib/ossl-modules/fips.so", "includes OpenSSL FIPS provider library").exists()

        expect("/usr/local/kong/openssl.cnf", "includes valid OpenSSL FIPS configuration") \
            .exists() \
            .text_content.matches("\[fips_sect\]") \
            .text_content.matches("module-mac = [A-F:\d]+")


def libc_libcpp_suites(expect, max_libc: str, max_libcxx: str, max_cxxabi: str):
    if max_libc:
        expect("**/*.so", "libc version is less than %s" % max_libc) \
            .version_requirement.key("libc.so.6").is_not().greater_than("GLIBC_%s" % max_libc) \
            .version_requirement.key("libdl.so.2").is_not().greater_than("GLIBC_%s" % max_libc) \
            .version_requirement.key("libpthread.so.0").is_not().greater_than("GLIBC_%s" % max_libc) \
            .version_requirement.key("librt.so.1").is_not().greater_than("GLIBC_%s" % max_libc) \

    if max_libcxx:
        expect("**/*.so", "glibcxx version is less than %s" % max_libcxx) \
            .version_requirement.key("libstdc++.so.6").is_not().greater_than("GLIBCXX_%s" % max_libcxx)

    if max_cxxabi:
        expect("**/*.so", "cxxabi version is less than %s" % max_cxxabi) \
            .version_requirement.key("libstdc++.so.6").is_not().greater_than("CXXABI_%s" % max_cxxabi)


def arm64_suites(expect):
    expect("**/*/**.so*", "Dynamic libraries are arm64 arch") \
        .arch.equals("AARCH64")

    expect("/usr/local/openresty/nginx/sbin/nginx", "Nginx is arm64 arch") \
        .arch.equals("AARCH64")
