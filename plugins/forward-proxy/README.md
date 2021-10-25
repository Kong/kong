# kong-plugin-enterprise-forward-proxy

Upstream HTTP/HTTPS Proxy support for Kong.

## Synopsis

This plugins allows Kong to connect through an intermediary HTTP/HTTPS proxy instead of directly to the upstream server.

## Configuration

Configuring the plugin is straightforward, you can add it on top of an existing service by executing the following request on your Kong server:

```bash
$ curl -X POST http://kong:8001/services/{service}/plugins \
    --data "name=forward-proxy" \
    --data "config.proxy_host=<proxy_host>"
    --data "config.proxy_port=<proxy_port>"
```

`service`: The `id` or `name` of the service that this plugin configuration will target.

You can add it on top of an existing route by executing the following request on your Kong server:

```bash
$ curl -X POST http://kong:8001/routes/{route}/plugins \
    --data "name=forward-proxy" \
    --data "config.proxy_host=<proxy_host>"
    --data "config.proxy_port=<proxy_port>"
```

`route`: The `id` or `name` of the route that this plugin configuration will target.

You can also apply it for every service using the `http://kong:8001/plugins/` endpoint.

| form parameter | default | description |
| --- | --- | --- |
| `name` | | The name of the plugin to use, in this case: `forward-proxy` |
| `config.proxy_host` | | The hostname or IP address of the forward proxy to which to connect |
| `config.proxy_port` | | The TCP port of the forward proxy to which to connect |
| `config.proxy_scheme` | `http` | The proxy scheme to use when connecting. Currently only `http` is supported |
| `config.https_verify ` | `false` | Whether the server certificate will be verified according to the CA certificates specified in `lua_ssl_trusted_certificate` |


## Notes

The plugin attempts to transparently replace upstream connections made by Kong core, sending the request instead to an intermediary forward proxy.


[badge-travis-url]: https://travis-ci.com/Kong/kong-plugin-enterprise-forward-proxy/branches
[badge-travis-image]: https://travis-ci.com/Kong/kong-plugin-enterprise-forward-proxy.svg?token=BfzyBZDa3icGPsKGmBHb&branch=master
