Name
====

The module is currently Kong only, and builds on top of the `lua-resty-dns` and the kong's `lua-resty-mlcache` library.

Table of Contents
=================

* [Name](#name)
* [APIs](#apis)
    * [new](#new)
    * [query](#query)

# APIs

The following APIs are for internal development use only within Kong. In the current version, the new DNS library still needs to be compatible with the original DNS library. Therefore, the functions listed below cannot be directly invoked. For example, the `_M:resolve` function in the following APIs will be replaced to ensure compatibility with the previous DNS library API interface specifications `_M.resolve`.

## new

**syntax:** *c, err = dns_client.new(opts)*
**context:** any

**Functionality:**

Creates a dns client object. Returns nil and a message string on error.

Perform a series of initialization operations:

* parse `host` file
* parse `resolv.conf` file (used by the underlying `lua-resty-dns` library)
* initialize multiple TTL options
* create a mlcache object and initialize it

**Input paramenters:**

`@opts` It accepts a options table argument. The following options are supported:

* TTL options
  * `valid_ttl`
    * same to the option `dns_valid_ttl` in kong.conf
  * `stale_ttl`
    * same to the option `dns_stale_ttl` in kong.conf
  * `empty_ttl`
    * same to the option `dns_not_found_ttl` in kong.conf
  * `bad_ttl`
    * same to the option `dns_error_ttl` in kong.conf
* `hosts` (default: `/etc/hosts`)
  * the path of `hosts` file
* `resolv_conf` (default: `/etc/resolv.conf`)
  * the path of `resolv.conf` file, it will be parsed and passed into the underlying `lua-resty-dns` library.
* `order` (default: `{ "LAST", "SRV", "A", "AAAA", "CNAME" }`)
  * the order in which to resolve different record types, it's similar to the option `dns_order` in kong.conf.
  * The `LAST` type means the type of the last successful lookup (for the specified name).
* `enable_ipv6` (default: `ture`)
  * whether to support IPv6 servers when when getting nameservers from `resolv.conf`
* options for the underlying `lua-resty-dns` library 
  * `retrans` (default: `5`)
    * the total number of times of retransmitting the DNS request when receiving a DNS response times out according to the timeout setting. When trying to retransmit the query, the next nameserver according to the round-robin algorithm will be picked up.
    * If not given, it is taken from `resolv.conf` option `options attempts:<value>`.
  * `timeout` (default: `2000`)
    * the time in milliseconds for waiting for the response for a single attempt of request transmission
    * If not given, it is taken from `resolv.conf` option `options timeout:<value>`. But note that its unit in `resolv.conf` is second.
  * `no_random` (default: `true`)
    * a boolean flag controls whether to randomly pick the nameserver to query first, if `true` will always start with the first nameserver listed. 
    * If not given, it is taken from `resolv.conf` option `rotate` (inverted).
  * `nameservers`
    * a list of nameservers to be used. Each nameserver entry can be either a single hostname string or a table holding both the hostname string and the port number. For exmaple, `{"8.8.8.8", {"8.8.4.4", 53} }`.
    * If not given, it is taken from `resolv.conf` option `nameserver`.

[Back to TOC](#table-of-contents)

## resolve

**syntax:** *answers, err, tries? = resolve(name, opts?, tries?)*
**context:** *rewrite_by_lua\*, access_by_lua\*, content_by_lua\*, ngx.timer.\*;*

**Functionality:**

Performs a DNS resolution

1. First, use the key `short:<name>:all` to query mlcache to see if there are any results available for quick use. If results are found, return them directly.
2. If there are no results available for quick use in the cache, then query all keys (`<name>:<type>`) extended from this domain name .
    1. The method for calculating extended keys is as follows:
        1. The domain `<name>` is extended based on the `ndots`, `search`, and `domain` settings in `resolv.conf`.
        2. The `<type>` is extended based on the `dns_order` parameter.
    2. Loop through all keys to query them. Once a usable result is found, return it. Also, store the DNS record result in mlcache with the key `short:<name>:all`.
        1. Use this key (`<name>:<type>`) to query mlcache. If it is not found, it triggers the L3 callback of `mlcache:get` to query the DNS server and process data that has expired but is still usable (`resolve_name_type_callback`).
        2. Use `mlcache:peek` to check if the missed and expired key still exists in the shared dictionary. If it does, return it directly to mlcache and trigger an asynchronous background task to update the expired data (`start_stale_update_task`). The maximum time that expired data can be reused is `stale_ttl`, but the maximum TTL returned to mlcache cannot exceed 60s. This way, if the expired key is not successfully updated by the background task after 60s, it can still be reused by calling the `resolve` function from the upper layer to trigger the L3 callback to continue executing this logic and initiate another background task for updating.
            1. For example, with a `stale_ttl` of 3600s, if the background task fails to update the record due to network issues during this time, and the upper-level application continues to call resolve to get the domain name result, it will trigger a background task to query the DNS result for that domain name every 60s, resulting in approximately 60 background tasks being triggered (3600s/60s).


**Return value:**

* Return value `answers, err`
  * Return one array-like Lua table contains all the records
  * Return one ip address and port from records if `opts.return_random = true`
    * In this scenario, `answers` would hold an address, while `err` would contain either a port number or an error message, like `address, port` or `nil, err`
  * If the server returns a non-zero error code, it will return `nil` and a string describing the error in this record.
    * For exmaple, `nil, "dns server error: name error"`, the server returned a result with error code 3 (NXDOMAIN).
  * In case of severe errors, such network error or server's malformed DNS record response, it will return `nil` and a string describing the error instead. For example:
      * `nil, "recursion detected for name: example.com:5"`, it detected a loop or recursion while attempting to resolve `example.com:CNAME`.
      * `nil, "dns server error: failed to send request to UDP server 10.0.0.1:53: timeout"`, there was a network issue.
* Return value and input parameter `@tries?`:
  * If provided as an empty table, it will be returned as a third result. This table will be an array containing the error message for each (if any) failed try.
    * For example, `[["lambda.ab-cdef-1.amazonaws.com:SRV","dns server error: 3 name error"], ["lambda.ab-cdef-1.amazonaws.com:A","dns server error: 3 name error"]]`, both attempts failed due to a DNS server error with error code 3 (NXDOMAIN), indicating a name error.

**Input parameters:**

* `@name`: the domain name to resolve
* `@opts`: It accepts a options table argument. The following options are supported:
  * `cache_only` (default: `false`)
    * control whether to solely retrieve data from the internal cache without querying to the nameserver
  * `return_random` (default: `true`)
    * control whether to return either a single randomly selected IP address or all available records
* `@tries?` : see the above section `Return value and input paramter @tries?`

[Back to TOC](#table-of-contents)
