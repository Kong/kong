This file will guide you through the process of installing Kong and its dependencies.

In order to run, Kong needs the following:
- [Lua][lua-install-url] `5.1`
- [Luarocks][luarocks-url] `2.2.0` **for lua 5.1**.
- [OpenResty](http://openresty.com/#Download) `1.7.7.2`
- [pcre][pcre-url]
- [openssl][openssl-url]
- [Cassandra][cassandra-url] `2.1`

#### Docker

Kong can run in [Docker][docker-url]. Image and instructions are on [mashape/docker-kong][docker-kong-url]

#### Linux

> To write

#### OS X

##### With Homebrew

If you don't have Lua 5.1 installed:

```bash
brew install lua51
ln /usr/local/bin/lua-5.1 /usr/local/bin/lua # alias lua-5.1 to lua (required for kong scripts)
```

We'll need Luarocks for Lua 5.1. The official Luarocks recipe only supports 5.2 now, so we'll use a custom recipe:

```bash
brew tap naartjie/luajit
brew install naartjie/luajit/luarocks-luajit --with-lua51
```

Now, let's intall openresty:

```bash
brew tap killercup/openresty
brew install ngx_openresty
ln /usr/local/bin/openresty /usr/local/bin/nginx # alias openresty to nginx (required for kong scripts)
```

If you wish to run Cassandra locally (you can also use our [Docker image](https://github.com/Mashape/docker-cassandra)):

```bash
brew install cassandra
# to start cassandra, just run `cassandra`
```

Other dependencies:

```bash
brew install pcre openssl
```

Finally, install Kong:

```bash
sudo make install
```

##### Raw OS X

> To write

[docker-url]: https://www.docker.com/
[docker-kong-url]: https://github.com/Mashape/docker-kong
[lua-install-url]: http://www.lua.org/download.html
[luarocks-url]: https://luarocks.org
[cassandra-url]: http://cassandra.apache.org/
[pcre-url]: http://www.pcre.org/
[openssl-url]: https://www.openssl.org/
