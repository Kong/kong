
def common_suites(expect, fips: bool = False):
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

    if not fips:
        expect("/usr/local/openresty/nginx/sbin/nginx", "nginx compiled with OpenSSL 3.1.x") \
            .nginx_compiled_openssl.matches("OpenSSL 3.1.\d") \
            .version_requirement.key("libssl.so.3").less_than("OPENSSL_3.2.0") \
            .version_requirement.key("libcrypto.so.3").less_than("OPENSSL_3.2.0") \
  
        expect("**/*.so", "dynamic libraries are compiled with OpenSSL 3.1.x") \
            .version_requirement.key("libssl.so.3").less_than("OPENSSL_3.2.0") \
            .version_requirement.key("libcrypto.so.3").less_than("OPENSSL_3.2.0") \


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
