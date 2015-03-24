This file will guide you through the process of installing Kong and its dependencies.

In order to run, Kong needs the following:
- [Lua][lua-install-url] `5.1`
- [Luarocks][luarocks-url] `2.2.0` **for lua 5.1**.
- [OpenResty](http://openresty.com/#Download) `1.7.10.1`
- [pcre][pcre-url]
- [openssl][openssl-url]
- [Cassandra][cassandra-url] `2.1`

#### Docker

Kong can run in [Docker][docker-url]. Image and instructions are on [mashape/docker-kong][docker-kong-url]

#### Linux

##### Debian

We need Lua 5.1 and luarocks (it's 2.0.0 but it'll do it):

```
apt-get install lua5.1 lua5.1-dev
```

Install luarocks:

```
wget http://luarocks.org/releases/luarocks-2.2.0.tar.gz
tar xzf luarocks-2.2.0.tar.gz
cd luarocks-2.2.0
./configure
make build
sudo make install
```

Install openresty prerequisites:

```
apt-get install libreadline-dev libncurses5-dev libpcre3-dev libssl-dev perl make
```

Install openresty:

```
wget http://openresty.org/download/ngx_openresty-1.7.10.1.tar.gz
tar xzf ngx_openresty-1.7.10.1.tar.gz
cd ngx_openresty-1.7.10.1/
./configure
make
sudo make install
```

Add nginx to your `$PATH`:

```
export PATH=$PATH:/usr/local/openresty/nginx/sbin
```

If you whish to run Cassandra locally, install it following the [Datastax instructions](http://www.datastax.com/documentation/cassandra/2.0/cassandra/install/installDeb_t.html) or using our [Docker image][docker-kong-url].

Finally, install Kong. Download [the latest release][kong-latest-url] and execute:

```
[sudo] make install
```

Now follow the "Usage" section of the README to start Kong.

#### OS X

##### With Homebrew

If you don't have Lua 5.1 installed:

```
brew install lua51
ln /usr/local/bin/lua5.1 /usr/local/bin/lua # alias lua5.1 to lua (required for kong scripts)
```

We'll need luarocks 2.2.0 for Lua 5.1. The official Luarocks recipe only supports 5.2 now, so we'll use a custom recipe:

```
brew tap naartjie/luajit
brew install naartjie/luajit/luarocks-luajit --with-lua51
```

Install openresty prerequisites:

```
brew install pcre openssl
```

Now, let's install openresty (it's 1.7.4.1, a new recipe would be welcomed):

```
brew tap killercup/openresty
brew install ngx_openresty
ln /usr/local/bin/openresty /usr/local/bin/nginx # alias openresty to nginx (required for kong scripts)
```

If you wish to run Cassandra locally (you can also use our [Docker image][docker-kong-url]):

```
brew install cassandra
# to start cassandra, just run `cassandra`
```

Finally, install Kong. Download [the latest release][kong-latest-url] and execute:

```
[sudo] make install
```

Now follow the "Usage" section of the README to start Kong.

##### Raw OS X

> To write

[docker-url]: https://www.docker.com/
[docker-kong-url]: https://github.com/Mashape/docker-kong
[docker-cassandra-url]: https://github.com/Mashape/docker-cassandra
[lua-install-url]: http://www.lua.org/download.html
[luarocks-url]: https://luarocks.org
[cassandra-url]: http://cassandra.apache.org/
[pcre-url]: http://www.pcre.org/
[openssl-url]: https://www.openssl.org/
[kong-latest-url]: https://github.com/Mashape/kong/releases
