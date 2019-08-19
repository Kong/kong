
### Prerequisites

ubuntu:

	apt-get install \
		build-essential \
		curl \
		git \
		libpcre3 \
		libyaml-dev \
		m4 \
		openssl \
		perl \
		procps \
		unzip \
		zlib1g-dev


Fedora:

	dnf install \
		automake \
		gcc \
		gcc-c++ \
		git \
		libyaml-devel \
		make \
		patch \
		pcre-devel \
		unzip \
		zlib-devel


### OpenResty

	git clone https://github.com/kong/openresty-build-tools

	cd openresty-build-tools
	./kong-ngx-build -p ~/build \
		--openresty 1.15.8.1 \
		--openssl 1.1.1c \
		--luarocks 3.1.3 \
		--pcre 8.43 \
		--openresty-patches fix/dyn-lightuserdata-mapping
