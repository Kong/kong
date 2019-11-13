# Kong Let's Encrypt Plugin

![Build Status](https://travis-ci.com/Kong/kong-plugin-letsencrypt.svg?branch=master)

This plugin allows Kong to apply cerificates from Let's Encrypt and serve dynamically.

### Using the Plugin

#### Enable the Plugin
```bash
$ curl http://localhost:8001/plugins -d name=letsencrypt -d config.account_email=yourname@example.com
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
$ echo q |openssl s_client -connect localhost -port 8443 -servername $NGROK_HOST 2>/dev/null|openssl x509 -text -noout
```

### Notes

- The plugin creates sni and certificate entity in Kong to serve certificate, as using the certificate plugin phase
to serve dynamic cert means to copy paste part of kong. Then dbless mode is not supported.
- Apart from above, the plugin can be used without db. Optional storages are `shm`, `redis`, `consul` and `vault`.
- It only supports http-01 challenge, meaning user will need a public IP and setup resolvable DNS. And Kong
needs to accept proxy traffic from 80 port.