[![Build Status][badge-travis-image]][badge-travis-url]

# Kong proxy-cache plugin

HTTP Proxy Caching for Kong

## Synopsis

This plugin provides a reverse proxy cache implementation for Kong. It caches
response entities based on configurable response code and content type, as
well as request method. It can cache per-Consumer or per-API. Cache entities
are stored for a configurable period of time, after which subsequent requests
to the same resource will re-fetch and re-store the resource. Cache entities
can also be forcefully purged via the Admin API prior to their expiration
time.

## Documentation

* [Documentation for the Proxy Cache plugin](https://docs.konghq.com/hub/kong-inc/proxy-cache/)

[badge-travis-url]: https://travis-ci.com/Kong/kong-plugin-proxy-cache/branches
[badge-travis-image]: https://travis-ci.com/Kong/kong-plugin-proxy-cache.svg?token=BfzyBZDa3icGPsKGmBHb&branch=master
