Name
====

The module is currently Kong only, and builds on top of the `lua-resty-dns` and kong's `lua-resty-mlcache` library.

Table of Contents
=================

* [Name](#name)
* [APIs](#apis)
    * [new](#new)
    * [resolve](#resolve)
    * [resolve_address](#resolve_address)

# APIs

The following APIs are for internal development use only within Kong. In the current version, the new DNS library still needs to be compatible with the original DNS library. Therefore, the functions listed below cannot be directly invoked. For example, the `_M:resolve` function in the following APIs will be replaced to ensure compatibility with the previous DNS library API interface specifications `_M.resolve`.

## new

**syntax:** *c, err = dns_client.new(opts)*  
**context:** any

**Functionality:**

Creates a dns client object. Returns `nil` and a message string on error.

Performs a series of initialization operations:

* parse `host` file,
* parse `resolv.conf` file (used by the underlying `lua-resty-dns` library),
* initialize multiple TTL options,
* create a mlcache object and initialize it.

**Input parameters:**

`@opts` It accepts a options table argument. The following options are supported:

* TTL options:
  * `valid_ttl`: same to the option `dns_valid_ttl` in `kong.conf`.
  * `stale_ttl`: same to the option `dns_stale_ttl` in `kong.conf`.
  * `empty_ttl`: same to the option `dns_not_found_ttl` in `kong.conf`.
  * `bad_ttl`: same to the option `dns_error_ttl` in `kong.conf`.
* `hosts`: (default: `/etc/hosts`)
  * the path of `hosts` file.
* `resolv_conf`: (default: `/etc/resolv.conf`)
  * the path of `resolv.conf` file, it will be parsed and passed into the underlying `lua-resty-dns` library.
* `order`: (default: `{ "SRV", "A", "AAAA" }`)
  * the order in which to resolve different record types, it's similar to the option `dns_order` in `kong.conf`.
* `enable_ipv6`: (default: `true`)
  * whether to support IPv6 servers when getting nameservers from `resolv.conf`.
* options for the underlying `lua-resty-dns` library:
  * `retrans`: (default: `5`)
    * the total number of times of retransmitting the DNS request when receiving a DNS response times out according to the timeout setting. When trying to retransmit the query, the next nameserver according to the round-robin algorithm will be picked up.
    * If not given, it is taken from `resolv.conf` option `options attempts:<value>`.
  * `timeout`: (default: `2000`)
    * the time in milliseconds for waiting for the response for a single attempt of request transmission.
    * If not given, it is taken from `resolv.conf` option `options timeout:<value>`. But note that its unit in `resolv.conf` is second.
  * `no_random`: (default: `true`)
    * a boolean flag controls whether to randomly pick the nameserver to query first. If `true`, it always starts with the first nameserver listed.
    * If not given, it is taken from `resolv.conf` option `rotate` (inverted).
  * `nameservers`:
    * a list of nameservers to be used. Each nameserver entry can be either a single hostname string or a table holding both the hostname string and the port number. For exmaple, `{"8.8.8.8", {"8.8.4.4", 53} }`.
    * If not given, it is taken from `resolv.conf` option `nameserver`.

[Back to TOC](#table-of-contents)

## resolve

**syntax:** *answers, err, tries? = resolve(qname, qtype, cache_only, tries?)*  
**context:** *rewrite_by_lua\*, access_by_lua\*, content_by_lua\*, ngx.timer.\**

**Functionality:**

Performs a DNS resolution.

1. First, use the key `<qname>:all` (or `<qname>:<qtype>` if `@qtype` is not `nil`) to query mlcache to see if there are any results available. If results are found, return them directly.
2. If there are no results available in the cache, it triggers the L3 callback of `mlcache:get` to query records from the DNS servers, details are as follows:
    1. Check if `<qname>` has an IP address in the `hosts` file, return if found.
    2. Check if `<qname>` is an IP address itself, return if true.
    3. Use `mlcache:peek` to check if the expired key still exists in the shared dictionary. If it does, return it directly to mlcache and trigger an asynchronous background task to update the expired data (`start_stale_update_task`). The maximum time that expired data can be reused is `stale_ttl`, but the maximum TTL returned to mlcache cannot exceed 60s. This way, if the expired key is not successfully updated by the background task after 60s, it can still be reused by calling the `resolve` function from the upper layer to trigger the L3 callback to continue executing this logic and initiate another background task for updating.
        1. For example, with a `stale_ttl` of 3600s, if the background task fails to update the record due to network issues during this time, and the upper-level application continues to call resolve to get the domain name result, it will trigger a background task to query the DNS result for that domain name every 60s, resulting in approximately 60 background tasks being triggered (3600s/60s).
    4. Query the DNS server, with `<name>:<type>` combinations:
            1. The `<name>` is extended according to settings in `resolv.conf`, such as `ndots`, `search`, and `domain`.
            2. The `<type>` is extended based on the `dns_order` parameter.

**Return value:**

* Return value `answers, err`:
  * Return one array-like Lua table contains all the records.
  * If the server returns a non-zero error code, it will return `nil` and a string describing the error in this record.
    * For exmaple, `nil, "dns server error: name error"`, the server returned a result with error code 3 (NXDOMAIN).
  * In case of severe errors, such network error or server's malformed DNS record response, it will return `nil` and a string describing the error instead. For example:
      * `nil, "dns server error: failed to send request to UDP server 10.0.0.1:53: timeout"`, there was a network issue.
* Return value and input parameter `@tries?`:
  * If provided as an empty table, it will be returned as a third result. This table will be an array containing the error message for each (if any) failed try.
    * For example, `[["lambda.ab-cdef-1.amazonaws.com:SRV","dns server error: 3 name error"], ["lambda.ab-cdef-1.amazonaws.com:A","dns server error: 3 name error"]]`, both attempts failed due to a DNS server error with error code 3 (NXDOMAIN), indicating a name error.

**Input parameters:**

* `@qname`: the domain name to resolve.
* `@qtype`: (optional: `nil` or DNS TYPE value)
  * specify the query type instead of `self.order` types.
* `@cache_only`: (optional: `boolean`)
  * control whether to solely retrieve data from the internal cache without querying to the nameserver.
* `@tries?`: see the above section `Return value and input paramter @tries?`.

[Back to TOC](#table-of-contents)

## resolve_address

**syntax:** *ip, port_or_err, tries? = resolve_address(name, port, cache_only, tries?)*  
**context:** *rewrite_by_lua\*, access_by_lua\*, content_by_lua\*, ngx.timer.\**

**Functionality:**

Performs a DNS resolution, and return a single randomly selected address (IP and port number).

When calling multiple times on cached records, it will apply load-balancing based on a round-robin (RR) scheme. For SRV records, this will be a _weighted_ round-robin (WRR) scheme (because of the weights it will be randomized). It will apply the round-robin schemes on each level individually.

**Return value:**

* Return value `ip, port_or_err`:
  * Return one IP address and port number from records.
  * Return `nil, err` if errors occur, with `err` containing an error message.
* Return value and input parameter `@tries?`: same as `@tries?` of `resolve` API.

**Input parameters:**

* `@name`: the domain name to resolve.
* `@port`: (optional: `nil` or port number)
  * default port number to return if none was found in the lookup chain (only SRV records carry port information, SRV with `port=0` will be ignored).
* `@cache_only`: (optional: `boolean`)
  * control whether to solely retrieve data from the internal cache without querying to the nameserver.

[Back to TOC](#table-of-contents)
