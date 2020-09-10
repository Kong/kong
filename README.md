# Kong ACME Plugin

![Build Status](https://travis-ci.com/Kong/kong-plugin-acme.svg?branch=master)

This plugin allows Kong to apply certificates from Let's Encrypt or any other ACMEv2 service
and serve dynamically. Renewal is handled with a configurable threshold time.

### Using the Plugin

#### Configure Kong

- Kong needs to listen 80 port or proxied by a load balancer that listens for 80 port.
- `lua_ssl_trusted_certificate` needs to be set in `kong.conf` to ensure the plugin can properly
verify Let's Encrypt API. The CA-bundle file is usually `/etc/ssl/certs/ca-certificates.crt` for
Ubuntu/Debian and `/etc/ssl/certs/ca-bundle.crt` for CentOS/Fedora/RHEL. If you are using Kong with Docker you can also 
set `KONG_LUA_SSL_TRUSTED_CERTIFICATE` as environment instead of changing `kong.conf`.

#### Enable the Plugin

For each the domain that needs a certificate, make sure `DOMAIN/.well-known/acme-challenge`
is mapped to a Route in Kong. You can check this by sending
`curl KONG_IP/.well-known/acme-challenge/x -H "host:DOMAIN"` and expect a response `Not found`.
From plugin version 0.2.4, you can also [use the Admin API](#create-certificates) to
verify the setup.
If not, add a Route and a dummy Service to catch this route.
```bash
# add a dummy service if needed
$ curl http://localhost:8001/services \
        -d name=acme-dummy \
        -d url=http://127.0.0.1:65535
# add a dummy route if needed
$ curl http://localhost:8001/routes \
        -d name=acme-dummy \
        -d paths[]=/.well-known/acme-challenge \
        -d service.name=acme-dummy

# add the plugin
$ curl http://localhost:8001/plugins \
        -d name=acme \
        -d config.account_email=yourname@yourdomain.com \
        -d config.tos_accepted=true \
        -d config.domains[]=my.secret.domains.com \
        -d config.domains[]=my.anoother.secret.domains.com
```

Note by setting `tos_accepted` to *true* implies that you have read and accepted
[terms of service](https://letsencrypt.org/repository/).

**This plugin can only be configured as a global plugin.** The plugin terminats
`/.well-known/acme-challenge/` path for matching domains. To create certificate 
and terminates challenge only for certain domains, please refer to the
[Plugin Config](#plugin-config) section.

#### Create certificates

Assume Kong proxy is accessible via http://mydomain.com and https://mydomain.com.

```bash
# Trigger asynchronous creation from proxy requests
# The following request returns immediately with Kong's default certificate
# Wait up to 1 minute for the background process to finish
$ curl https://mydomain.com -k

# OR create from Admin API synchronously with version >= 0.2.4
# User can also use this endpoint to force "renew" a certificate
$ curl http://localhost:8001/acme -d host=mydomain.com

# Furthermore, it's possible to run a sanity test on your Kong setup
# before creating any certificate
$ curl http://localhost:8001/acme -d host=mydomain.com -d test_http_challenge_flow=true

$ curl https://mydomain.com
# Now gives you a valid Let's Encrypt certicate
```

#### Renew certificates

The plugin automatically renews all certificate that are due for renewal everyday. Note the
renewal config is stored in configured storage backend. If the storage is cleared or modified
outside of Kong, renewal might not properly.

It's also possible to actively trigger the renewal starting version 0.2.4. The following request
schedules renewal in background and return immediately.

```bash
$ curl http://localhost:8001/acme -XPATCH
```

### Plugin Config

Name                | Required   | Default | Description
-------------------:|------------|------------|------------
config.account_email| Yes        |            | The account identifier, can be reused in different plugin instance.
config.api_uri      |            |  `"https://acme-v02.api.letsencrypt.org/directory"`   | The ACMEv2 API endpoint to use. Users can specify the [Let's Encrypt staging environment](https://letsencrypt.org/docs/staging-environment/) (`https://acme-staging-v02.api.letsencrypt.org/directory`) for testing. Note that Kong doesn't automatically delete staging certificates: if you use same domain to test and use in production, you will need to delete those certificates manaully after test.
config.cert_type    |            |  `"rsa"`   | The certificate type to create. The possible values are `"rsa"` for RSA certificate or `"ecc"` for EC certificate.
config.domains      |            | `[]`       | The list of domains to create certificate for. To match subdomains under `example.com`, use `*.example.com`. Regex pattern is not supported. Note this config is only used to match domains, not to specify the Common Name or Subject Alternative Name to create certifcates; each domain will have its own certificate.
config.renew_threshold_days|     |  `14`      | Days before expire to renew the certificate.
config.fail_backoff_minutes|     |  `5`       | Minutes to wait for each domain that fails to create a certificate. This applies to both new certificate and renewal.
config.storage      |            |  `"shm"`   | The backend storage type to use. The possible values are `"kong"`, `"shm"`, `"redis"`, `"consul"`, or `"vault"`. In DB-less mode, `"kong"` storage is unavailable. Note that `"shm"` storage does not persist during Kong restarts and does not work for Kong running on different machines, so consider using one of `"kong"`, `"redis"`, `"consul"`, or `"vault"` in production.
config.storage_config|           | (See below)| Storage configs for each backend storage.
config.tos_accepted |            | `false`    | If you are using Let's Encrypt, you must set this to true to agree the [Terms of Service](https://letsencrypt.org/repository/).

`config.storage_config` is a table for all posisble storage types, by default it is:
```json
    "storage_config": {
        "kong": {},
        "shm": {
            "shm_name": "kong"
        },
        "redis": {
            "auth": null,
            "port": 6379,
            "database": 0,
            "host": "127.0.0.1"
        },
        "consul": {
            "host": "127.0.0.1",
            "port": 8500,
            "token": null,
            "kv_path": "acme",
            "timeout": 2000,
            "https": false
        },
        "vault": {
            "host": "127.0.0.1",
            "port": 8200,
            "token": null,
            "kv_path": "acme",
            "timeout": 2000,
            "https": false,
            "tls_verify": true,
            "tls_server_name": null
        },
    }
```

To configure storage type other than `kong`, please refer to [lua-resty-acme](https://github.com/fffonion/lua-resty-acme#storage-adapters).

Note `tls_verify` and `tls_server_name` parameters for Vault are only supported from plugin version 0.2.7.

Here's a sample declarative configuration with `redis` as storage:

```yaml
_format_version: "1.1"
# this section is not necessary if there's already a route that matches
# /.well-known/acme-challenge path with http protocol
services:
  - name: acme-dummy
    url: http://127.0.0.1:65535
    routes:
      - name: acme-dummy
        protocols:
          - http
        paths:
          - /.well-known/acme-challenge
plugins:
  - name: acme
    config:
      account_email: example@myexample.com
      domains:
        - "*.example.com"
        - "example.com"
      tos_accepted: true
      storage: redis
      storage_config:
        redis:
          host: redis.service
          port: 6379
```

### Local testing and development

#### Run ngrok

[ngrok](https://ngrok.com) exposes a local URL to the internet. [Download ngrok](https://ngrok.com/download) and install.

*`ngrok` is only needed for local testing or development, it's **not** a requirement for the plugin itself.*

Run ngrok with

```bash
$ ./ngrok http localhost:8000
# Shows something like
# ...
# Forwarding                    http://e2e034a5.ngrok.io -> http://localhost:8000
# Forwarding                    https://e2e034a5.ngrok.io -> http://localhost:8000
# ...
# Substitute "e2e034a5.ngrok.io" with the host shows in your ngrok output
$ export NGROK_HOST=e2e034a5.ngrok.io
```

Leave the process running.

#### Configure Route and Service

```bash
$ curl http://localhost:8001/services -d name=acme-test -d url=http://mockbin.org
$ curl http://localhost:8001/routes -d service.name=acme-test -d hosts=$NGROK_HOST
```

#### Enable Plugin

```bash
$ curl localhost:8001/plugins -d name=acme \
                                -d config.account_email=test@test.com \
                                -d config.tos_accepted=true \
                                -d config.domains[]=$NGROK_HOST
```

#### Trigger creation of certificate

```bash
$ curl https://$NGROK_HOST:8443 --resolve $NGROK_HOST:8443:127.0.0.1 -vk
# Wait for several seconds
```

#### Check new certificate

```bash
$ echo q |openssl s_client -connect localhost -port 8443 -servername $NGROK_HOST 2>/dev/null |openssl x509 -text -noout
```

### Notes

- In database mode, the plugin creates SNI and Certificate entity in Kong to
serve certificate. If SNI or Certificate for current request is already set
in database, they will be overwritten.
- In DB-less mode, the plugin takes over certificate handling, if the SNI or
Certificate entity is already defined in Kong, they will be overrided from
response.
- The plugin only supports http-01 challenge, meaning user will need a public
IP and setup resolvable DNS. Kong also needs to accept proxy traffic from port `80`.
Also, note that wildcard or star certificate is not supported, each domain will have its
own certificate.
