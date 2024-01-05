return [[
pid pids/nginx.pid;
> if wasm and wasm_dynamic_module then
load_module $(wasm_dynamic_module);
> end

error_log ${{PROXY_ERROR_LOG}} ${{LOG_LEVEL}};

# injected nginx_main_* directives
> for _, el in ipairs(nginx_main_directives) do
$(el.name) $(el.value);
> end

include 'nginx-inject.conf';

events {
    # injected nginx_events_* directives
> for _, el in ipairs(nginx_events_directives) do
    $(el.name) $(el.value);
> end
}

> if wasm then
wasm {
> for _, el in ipairs(nginx_wasm_main_shm_kv_directives) do
  shm_kv $(el.name) $(el.value);
> end

> for _, module in ipairs(wasm_modules_parsed) do
  module $(module.name) $(module.path);
> end

> for _, el in ipairs(nginx_wasm_main_directives) do
  $(el.name) $(el.value);
> end

> if #nginx_wasm_wasmtime_directives > 0 then
  wasmtime {
> for _, el in ipairs(nginx_wasm_wasmtime_directives) do
    flag $(el.name) $(el.value);
> end
  }
> end -- wasmtime

> if #nginx_wasm_v8_directives > 0 then
  v8 {
> for _, el in ipairs(nginx_wasm_v8_directives) do
    flag $(el.name) $(el.value);
> end
  }
> end -- v8

> if #nginx_wasm_wasmer_directives > 0 then
  wasmer {
> for _, el in ipairs(nginx_wasm_wasmer_directives) do
    flag $(el.name) $(el.value);
> end
  }
> end -- wasmer

}
> end

> if role == "control_plane" or #proxy_listeners > 0 or #admin_listeners > 0 or #status_listeners > 0 then
http {
    include 'nginx-kong.conf';
}
> end

> if #stream_listeners > 0 or cluster_ssl_tunnel then
stream {
> if #stream_listeners > 0 then
    include 'nginx-kong-stream.conf';
> end

> if cluster_ssl_tunnel then
    server {
        listen unix:${{PREFIX}}/cluster_proxy_ssl_terminator.sock;

        proxy_pass ${{cluster_ssl_tunnel}};
        proxy_ssl on;
        # as we are essentially talking in HTTPS, passing SNI should default turned on
        proxy_ssl_server_name on;
> if proxy_server_ssl_verify then
        proxy_ssl_verify on;
> if lua_ssl_trusted_certificate_combined then
        proxy_ssl_trusted_certificate '${{LUA_SSL_TRUSTED_CERTIFICATE_COMBINED}}';
> end
        proxy_ssl_verify_depth 5; # 5 should be sufficient
> else
        proxy_ssl_verify off;
> end
        proxy_socket_keepalive on;
    }
> end -- cluster_ssl_tunnel

}
> end
]]
