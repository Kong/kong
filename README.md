# Apenode 

lua-resty-apenode - Lua Apenode core dependencies

[![The beginning of a new era](http://img.youtube.com/vi/U2iiPpcwfCA/0.jpg)](http://www.youtube.com/watch?v=U2iiPpcwfCA)

# Installation

* [Download](http://openresty.com/#Download) the latest version of OpenResty and install it.
* Execute `make install` to install the Apenode

# Running

You can run the Apenode in two different modes:

* In background, with: `sudo nginx`
* Or in foreground, with: `sudo nginx -g "daemon off;"`

By default it will be running on port `8000`, so navigate to [http://localhost:8000/](http://localhost:8000/) after starting it.