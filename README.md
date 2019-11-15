# Kong ACME Plugin

![Build Status](https://travis-ci.com/Kong/kong-plugin-letsencrypt.svg?branch=master)

This plugin allows Kong to apply cerificates from Let's Encrypt or any other ACMEv2 service
and serve dynamically. Renew is handled with a configurable threshold time.

### Using the Plugin

#### Configure Kong

- Kong needs to listen 80 port or proxied by a load balancer that listens for 80 port.
- `lua_ssl_trusted_certificate` needs to be set in `kong.conf` to ensure the plugin can properly
verify Let's Encrypt API.

#### Enable the Plugin
```bash
$ curl http://localhost:8001/plugins -d name=acme -d config.account_email=yourname@example.com
```

The plugin can be enabled globally or per Service/Route.
When not enabled globally, it should at least be enabled on a route matching `http://HOST/.well-known/acme-challenge`
where `HOST` is the hostname that needs certificate.

#### Trigger creation of certificate

Assume Kong proxy is accessible via http://mydomain.com and https://mydomain.com.

```bash
$ curl https://mydomain.com -k
# Returns Kong's default certificate
# Wait up to 1 minute
$ curl https://mydomain.com
# Now gives you a valid Let's Encrypt certicate
```

### Plugin Config

Name                | Required   | Default | Description
-------------------:|------------|------------|------------
config.account_email| Yes        |            | The account identifier, can be reused in different plugin instance.
config.api_uri      |            |  `"https://acme-v02.api.letsencrypt.org"`   | The ACMEv2 API endpoint to use, user might use [Let's Encrypt staging environemnt](https://letsencrypt.org/docs/staging-environment/) during testing.
config.cert_type    |            |  `"rsa"`   | The certificate to recreate, choice of `"rsa"` or `"ecc"`.
config.renew_threshold_days|     |  `14`      | Days before expire to renew the certificate.
config.storage      |            |  `"kong"`  | The backend storage type to use, choice of `"kong"`, `"shm"`, `"redis"`, `"consul"` or `"vault"`
config.storage_config|           | (See below)| Storage configs for each backend storage.

`config.storage_config` is a hash for all posisble storage types, by default it is:
```lua
    storage_config = {
        redis = {},
        shm = {
            shm_name = kong
        },
        vault = {
            https = true,
        },
        kong = {},
        consul = {
            https = true,
        }
    }
```

To use storage type other than `kong`, please refer to [lua-resty-acme](https://github.com/fffonion/lua-resty-acme#storage-adapters).

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
# Substitute with the host shows above
$ export NGROK_HOST=e2e034a5.ngrok.io
```

Leave the process running.

#### Configure Route and Service

```bash
$ curl http://localhost:8001/services -d name=le-test -d url=http://mockbin.org
$ curl http://localhost:8001/routes -d service.name=le-test -d hosts=$NGROK_HOST
```

#### Enable Plugin on the Service

```bash
$ curl localhost:8001/plugins -d name=letsencrypt -d service.name=le-test \
                                -d config.account_email=test@test.com
```

#### Trigger creation of certificate

```bash
$ curl https://$NGROK_HOST:8443 --resolve $NGROK_HOST:8443:127.0.0.1 -vk
# Wait for several seconds
```

#### Check new certificate

```bash
$ echo q |openssl s_client -connect localhost -port 8443 -servername $NGROK_HOST 2>/dev/nil|openssl x509 -text -noout
```

### Notes

- The plugin creates sni and certificate entity in Kong to serve certificate, as using the certificate plugin phase
to serve dynamic cert means to copy paste part of kong. Then dbless mode is not supported (currently).
- Apart from above, the plugin can be used without db. Optional storages are `shm`, `redis`, `consul` and `vault`.
- It only supports http-01 challenge, meaning user will need a public IP and setup resolvable DNS. And Kong
needs to accept proxy traffic from 80 port.