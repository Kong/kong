-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]


return require("kong.tools.sandbox.require.lua") .. [[
kong.enterprise_edition.tools.redis.v2

argon2
bcrypt

cjson cjson.safe

lyaml

kong.constants kong.concurrency kong.meta

kong.tools.cjson kong.tools.gzip       kong.tools.ip     kong.tools.mime_type
kong.tools.rand  kong.tools.sha256     kong.tools.string kong.tools.table
kong.tools.time  kong.tools.timestamp  kong.tools.uri    kong.tools.uuid
kong.tools.yield

ngx.base64 ngx.re ngx.req ngx.resp ngx.semaphore

pgmoon pgmoon.arrays pgmoon.hstore

pl.stringx pl.tablex

resty.aes    resty.lock   resty.md5    resty.memcached resty.mysql  resty.random
resty.redis  resty.sha    resty.sha1   resty.sha224    resty.sha256 resty.sha384
resty.sha512 resty.string resty.upload

resty.core.time resty.dns.resolver resty.lrucache resty.lrucache.pureffi

resty.ada resty.ada.search

resty.aws                                     resty.aws.utils
resty.aws.config                              resty.aws.request.validate
resty.aws.request.build                       resty.aws.request.sign
resty.aws.request.execute                     resty.aws.request.signatures.utils
resty.aws.request.signatures.v4               resty.aws.request.signatures.presign
resty.aws.request.signatures.none             resty.aws.service.rds.signer
resty.aws.credentials.Credentials             resty.aws.credentials.ChainableTemporaryCredentials
resty.aws.credentials.CredentialProviderChain resty.aws.credentials.EC2MetadataCredentials
resty.aws.credentials.EnvironmentCredentials  resty.aws.credentials.SharedFileCredentials
resty.aws.credentials.RemoteCredentials       resty.aws.credentials.TokenFileWebIdentityCredentials
resty.aws.raw-api.region_config_data

resty.azure                                        resty.azure.config
resty.azure.utils                                  resty.azure.credentials.Credentials
resty.azure.credentials.ClientCredentials          resty.azure.credentials.WorkloadIdentityCredentials
resty.azure.credentials.ManagedIdentityCredentials resty.azure.api.keyvault
resty.azure.api.secrets                            resty.azure.api.keys
resty.azure.api.certificates                       resty.azure.api.auth
resty.azure.api.request.build                      resty.azure.api.request.execute
resty.azure.api.response.handle

resty.cookie

resty.gcp resty.gcp.request.credentials.accesstoken resty.gcp.request.discovery

resty.http resty.http_connect resty.http_headers

resty.ipmatcher
resty.jit-uuid
resty.jq

resty.jwt resty.evp resty.jwt-validators resty.hmac

resty.passwdqc
resty.session

resty.rediscluster resty.xmodem

resty.openssl                            resty.openssl.asn1
resty.openssl.bn                         resty.openssl.cipher
resty.openssl.ctx                        resty.openssl.dh
resty.openssl.digest                     resty.openssl.ec
resty.openssl.ecx                        resty.openssl.err
resty.openssl.hmac                       resty.openssl.kdf
resty.openssl.mac                        resty.openssl.objects
resty.openssl.param                      resty.openssl.pkcs12
resty.openssl.pkey                       resty.openssl.provider
resty.openssl.rand                       resty.openssl.rsa
resty.openssl.ssl                        resty.openssl.ssl_ctx
resty.openssl.ssl_ctx                    resty.openssl.stack
resty.openssl.version                    resty.openssl.x509
resty.openssl.x509.altname               resty.openssl.x509.chain
resty.openssl.x509.crl                   resty.openssl.x509.csr
resty.openssl.x509.name                  resty.openssl.x509.revoked
resty.openssl.x509.store                 resty.openssl.x509.extension
resty.openssl.x509.extension.dist_points resty.openssl.x509.extension.info_access

socket.url

tablepool

version

xmlua
]]
