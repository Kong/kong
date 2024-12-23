-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]


return require("kong.tools.sandbox.environment.lua") .. [[
kong.cache.get        kong.cache.get_bulk         kong.cache.probe
kong.cache.invalidate kong.cache.invalidate_local kong.cache.safe_set
kong.cache.renew

kong.client.authenticate                     kong.client.authenticate_consumer_group_by_consumer_id
kong.client.get_consumer                     kong.client.get_consumer_group
kong.client.get_consumer_groups              kong.client.get_credential
kong.client.get_forwarded_ip                 kong.client.get_forwarded_port
kong.client.get_ip                           kong.client.get_port
kong.client.get_protocol                     kong.client.load_consumer
kong.client.set_authenticated_consumer_group kong.client.set_authenticated_consumer_groups

kong.client.tls.disable_session_reuse      kong.client.tls.get_full_client_certificate_chain
kong.client.tls.request_client_certificate kong.client.tls.set_client_verify

kong.cluster.get_id

kong.db.certificates.cache_key           kong.db.certificates.select
kong.db.certificates.select_by_cache_key
kong.db.consumers.cache_key              kong.db.consumers.select
kong.db.consumers.select_by_cache_key    kong.db.consumers.select_by_custom_id
kong.db.consumers.select_by_username     kong.db.consumers.select_by_username_ignore_case
kong.db.keys.cache_key                   kong.db.keys.select
kong.db.keys.select_by_cache_key         kong.db.keys.select_by_name
kong.db.plugins.cache_key                kong.db.plugins.select
kong.db.plugins.select_by_cache_key      kong.db.plugins.select_by_instance_name
kong.db.routes.cache_key                 kong.db.routes.select
kong.db.routes.select_by_cache_key       kong.db.routes.select_by_name
kong.db.services.cache_key               kong.db.services.select
kong.db.services.select_by_cache_key     kong.db.services.select_by_name
kong.db.snis.cache_key                   kong.db.snis.select
kong.db.snis.select_by_cache_key         kong.db.snis.select_by_name
kong.db.targets.cache_key                kong.db.targets.select
kong.db.targets.select_by_cache_key      kong.db.targets.select_by_target
kong.db.upstreams.cache_key              kong.db.upstreams.select
kong.db.upstreams.select_by_cache_key    kong.db.upstreams.select_by_name

kong.default_workspace

kong.dns.resolve kong.dns.toip

kong.ip.is_trusted

kong.jwe.decode kong.jwe.decrypt kong.jwe.encrypt

kong.log.alert  kong.log.crit      kong.log.debug
kong.log.emerg  kong.log.err       kong.log.info
kong.log.notice kong.log.serialize kong.log.set_serialize_value
kong.log.warn

kong.log.deprecation.write

kong.log.inspect.on kong.log.inspect.off

kong.nginx.get_statistics kong.nginx.get_subsystem

kong.node.get_hostname kong.node.get_id kong.node.get_memory_stats

kong.plugin.get_id

kong.request.get_body             kong.request.get_forwarded_host
kong.request.get_forwarded_path   kong.request.get_forwarded_port
kong.request.get_forwarded_prefix kong.request.get_forwarded_scheme
kong.request.get_header           kong.request.get_headers
kong.request.get_host             kong.request.get_http_version
kong.request.get_method           kong.request.get_path
kong.request.get_path_with_query  kong.request.get_port
kong.request.get_query            kong.request.get_query_arg
kong.request.get_raw_body         kong.request.get_raw_path
kong.request.get_raw_query        kong.request.get_scheme
kong.request.get_start_time       kong.request.get_uri_captures

kong.response.add_header   kong.response.clear_header
kong.response.error        kong.response.exit
kong.response.get_header   kong.response.get_headers
kong.response.get_raw_body kong.response.get_source
kong.response.get_status   kong.response.set_header
kong.response.set_headers  kong.response.set_raw_body
kong.response.set_status

kong.router.get_route kong.router.get_service

kong.service.set_retries               kong.service.set_target
kong.service.set_target_retry_callback kong.service.set_timeouts
kong.service.set_tls_cert_key          kong.service.set_tls_cert_key
kong.service.set_tls_verify            kong.service.set_tls_verify_depth
kong.service.set_tls_verify_store      kong.service.set_tls_verify_store
kong.service.set_upstream

kong.service.request.add_header      kong.service.request.clear_header
kong.service.request.clear_query_arg kong.service.request.enable_buffering
kong.service.request.set_body        kong.service.request.set_header
kong.service.request.set_headers     kong.service.request.set_method
kong.service.request.set_path        kong.service.request.set_query
kong.service.request.set_raw_body    kong.service.request.set_raw_query
kong.service.request.set_scheme

kong.service.response.get_body    kong.service.response.get_header
kong.service.response.get_headers kong.service.response.get_raw_body
kong.service.response.get_status

kong.table.clear kong.table.merge

kong.telemetry.log

kong.tracing.create_span     kong.tracing.get_sampling_decision
kong.tracing.link_span       kong.tracing.process_span
kong.tracing.set_active_span kong.tracing.set_should_sample
kong.tracing.start_span

kong.vault.get kong.vault.is_reference kong.vault.parse_reference
kong.vault.try kong.vault.update

kong.version kong.version_num

kong.websocket.client.close                kong.websocket.client.drop_frame
kong.websocket.client.get_frame            kong.websocket.client.set_frame_data
kong.websocket.client.set_max_payload_size kong.websocket.client.set_status

kong.websocket.upstream.close                kong.websocket.upstream.drop_frame
kong.websocket.upstream.get_frame            kong.websocket.upstream.set_frame_data
kong.websocket.upstream.set_max_payload_size kong.websocket.upstream.set_status

ngx.AGAIN                     ngx.ALERT
ngx.CRIT                      ngx.DEBUG
ngx.DECLINED                  ngx.DONE
ngx.EMERG                     ngx.ERR
ngx.ERROR                     ngx.HTTP_ACCEPTED
ngx.HTTP_BAD_GATEWAY          ngx.HTTP_BAD_REQUEST
ngx.HTTP_CLOSE                ngx.HTTP_CONFLICT
ngx.HTTP_CONTINUE             ngx.HTTP_COPY
ngx.HTTP_CREATED              ngx.HTTP_DELETE
ngx.HTTP_FORBIDDEN            ngx.HTTP_GATEWAY_TIMEOUT
ngx.HTTP_GET                  ngx.HTTP_GONE
ngx.HTTP_HEAD                 ngx.HTTP_ILLEGAL
ngx.HTTP_INSUFFICIENT_STORAGE ngx.HTTP_INTERNAL_SERVER_ERROR
ngx.HTTP_LOCK                 ngx.HTTP_METHOD_NOT_IMPLEMENTED
ngx.HTTP_MKCOL                ngx.HTTP_MOVE
ngx.HTTP_MOVED_PERMANENTLY    ngx.HTTP_MOVED_TEMPORARILY
ngx.HTTP_NOT_ACCEPTABLE       ngx.HTTP_NOT_ALLOWED
ngx.HTTP_NOT_FOUND            ngx.HTTP_NOT_IMPLEMENTED
ngx.HTTP_NOT_MODIFIED         ngx.HTTP_NO_CONTENT
ngx.HTTP_OK                   ngx.HTTP_OPTIONS
ngx.HTTP_PARTIAL_CONTENT      ngx.HTTP_PATCH
ngx.HTTP_PAYMENT_REQUIRED     ngx.HTTP_PERMANENT_REDIRECT
ngx.HTTP_POST                 ngx.HTTP_PROPFIND
ngx.HTTP_PROPPATCH            ngx.HTTP_PUT
ngx.HTTP_REQUEST_TIMEOUT      ngx.HTTP_SEE_OTHER
ngx.HTTP_SERVICE_UNAVAILABLE  ngx.HTTP_SPECIAL_RESPONSE
ngx.HTTP_SWITCHING_PROTOCOLS  ngx.HTTP_TEMPORARY_REDIRECT
ngx.HTTP_TOO_MANY_REQUESTS    ngx.HTTP_TRACE
ngx.HTTP_UNAUTHORIZED         ngx.HTTP_UNLOCK
ngx.HTTP_UPGRADE_REQUIRED     ngx.HTTP_VERSION_NOT_SUPPORTED
ngx.INFO                      ngx.NOTICE
ngx.OK                        ngx.STDERR
ngx.WARN

ngx.cookie_time   ngx.crc32_long      ngx.crc32_short   ngx.decode_args
ngx.decode_base64 ngx.encode_args     ngx.encode_base64 ngx.eof
ngx.escape_uri    ngx.exit            ngx.flush         ngx.get_phase
ngx.get_raw_phase ngx.hmac_sha1       ngx.http_time     ngx.localtime
ngx.log           ngx.md5             ngx.md5_bin       ngx.now
ngx.null          ngx.parse_http_time ngx.print         ngx.quote_sql_str
ngx.redirect      ngx.say             ngx.send_headers  ngx.sha1_bin
ngx.sleep         ngx.time            ngx.today         ngx.unescape_uri
ngx.update_time   ngx.utctime

ngx.config.debug     ngx.config.nginx_version ngx.config.ngx_lua_version
ngx.config.subsystem

ngx.location.capture ngx.location.capture_multi

ngx.re.find ngx.re.gmatch ngx.re.gsub ngx.re.match ngx.re.sub

ngx.req.append_body   ngx.req.clear_header  ngx.req.discard_body
ngx.req.finish_body   ngx.req.get_body_data ngx.req.get_body_file
ngx.req.get_headers   ngx.req.get_method    ngx.req.get_post_args
ngx.req.get_uri_args  ngx.req.http_version  ngx.req.init_body
ngx.req.is_internal   ngx.req.raw_header    ngx.req.read_body
ngx.req.set_body_data ngx.req.set_body_file ngx.req.set_header
ngx.req.set_method    ngx.req.set_uri       ngx.req.set_uri_args
ngx.req.socket        ngx.req.start_time    ngx.resp.get_headers

ngx.thread.kill ngx.thread.spawn ngx.thread.wait

ngx.socket.connect ngx.socket.stream ngx.socket.tcp ngx.socket.udp

ngx.worker.count ngx.worker.exiting ngx.worker.id ngx.worker.pid
ngx.worker.pids
]]
