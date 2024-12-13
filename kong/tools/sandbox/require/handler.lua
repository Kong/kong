-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]


return require("kong.tools.sandbox.require.lua") .. [[
kong.enterprise_edition.tools.redis.v2

cjson cjson.safe

lyaml

kong.constants kong.concurrency kong.meta

kong.tools.cjson kong.tools.gzip       kong.tools.ip     kong.tools.mime_type
kong.tools.rand  kong.tools.sha256     kong.tools.string kong.tools.table
kong.tools.time  kong.tools.timestamp  kong.tools.uri    kong.tools.uuid
kong.tools.yield

ngx.base64 ngx.req ngx.resp ngx.semaphore

pgmoon pgmoon.arrays pgmoon.hstore

pl.stringx pl.tablex

resty.aes    resty.lock   resty.md5    resty.memcached resty.mysql  resty.random
resty.redis  resty.sha    resty.sha1   resty.sha224    resty.sha256 resty.sha384
resty.sha512 resty.string resty.upload

resty.core.time resty.dns.resolver resty.lrucache resty.lrucache.pureffi

resty.ada resty.ada.search
resty.aws
resty.azure
resty.cookie
resty.evp
resty.gcp
resty.http
resty.ipmatcher
resty.jit-uuid
resty.jq
resty.jwt
resty.passwdqc
resty.session
resty.rediscluster

resty.openssl        resty.openssl.bn      resty.openssl.cipher resty.openssl.digest
resty.openssl.hmac   resty.openssl.kdf     resty.openssl.mac    resty.openssl.pkey
resty.openssl.pkcs12 resty.openssl.objects resty.openssl.rand   resty.openssl.version
resty.openssl.x509

socket.url

tablepool

version

xmlua
]]
