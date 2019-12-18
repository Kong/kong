# Kong ACME Plugin

![Build Status](https://travis-ci.com/Kong/kong-plugin-acme.svg?branch=master)

This plugin allows Kong to apply cerificates from Let's Encrypt or any other ACMEv2 service
and serve dynamically. Renew is handled with a configurable threshold time.

### Using the Plugin

#### Configure Kong

- Kong needs to listen 80 port or proxied by a load balancer that listens for 80 port.
- `lua_ssl_trusted_certificate` needs to be set in `kong.conf` to ensure the plugin can properly
verify Let's Encrypt API. The CA-bundle file is usually `/etc/ssl/certs/ca-certificates.crt` for
Ubuntu/Debian and `/etc/ssl/certs/ca-bundle.crt` for CentOS/Fedora/RHEL.

#### Enable the Plugin
```bash
$ curl http://localhost:8001/plugins \
        -d name=acme \
        -d config.account_email=yourname@yourdomain.com \
        -d config.tos_accepted=true \
        -d config.domains[]=my.secret.domains.com
```

**This plugin can only be configured as a global plugin.** The plugin terminats
`/.well-known/acme-challenge/` path for matching domains. To create certificate 
and terminates challenge only for certain domains, please refer to the
[Plugin Config](#plugin-config) section.

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
config.cert_type    |            |  `"rsa"`   | The certificate type to create, choice of `"rsa"` for RSA certificate or `"ecc"` for EC certificate.
config.domains      |            | `[]`       | The list of domains to create certificate for. Wildcard domain like `*.example.com` is also supported. Regex pattern is not supported.
config.renew_threshold_days|     |  `14`      | Days before expire to renew the certificate.
config.storage      |            |  `"shm"`   | The backend storage type to use, choice of `"kong"`, `"shm"`, `"redis"`, `"consul"` or `"vault"`. In dbless mode, `"kong"` storage is unavailable.
config.storage_config|           | (See below)| Storage configs for each backend storage.
config.tos_accepted |            | `false`    | If you are using Let's Encrypt, you must set this to true to agree the [Terms of Service](https://letsencrypt.org/repository/).

`config.storage_config` is a table for all posisble storage types, by default it is:
```lua
    storage_config = {
        kong = {},
        shm = {
            shm_name = kong
        },
        redis = {
            host = '127.0.0.1',
            port = 6379,
            database = 0,
            -- Redis authentication key
            auth = nil,
        },
        consul = {
            host = '127.0.0.1',
            port = 8500,
            -- kv prefix path
            kv_path = "acme",
            -- Consul ACL token
            token = nil,
            -- timeout in ms
            timeout = 2000,
        }
        vault = {
            host = '127.0.0.1',
            port = 8200,
            -- secrets kv prefix path
            kv_path = "acme",
            -- Vault token
            token = nil,
            -- timeout in ms
            timeout = 2000,
        },
    }
```

If you are using a cluster of Kong (multiple Kong instances running on different machines),
consider using one of `"kong"`, `"redis"`, `"consul"` or `"vault"` to support inter-cluster communication.

To configure storage type other than `kong`, please refer to [lua-resty-acme](https://github.com/fffonion/lua-resty-acme#storage-adapters).

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
IP and setup resolvable DNS. And Kong needs to accept proxy traffic from 80 port.