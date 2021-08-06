# due to makefile omission in Kong grpcurl will not get installed
# on 1.3 through 2.0. So add manually if not installed already.
# see: https://github.com/Kong/kong/pull/5857

if [ ! -f /kong/bin/grpcurl ]; then
  echo grpcurl not found, now adding...
  curl -s -S -L https://github.com/fullstorydev/grpcurl/releases/download/v1.3.0/grpcurl_1.3.0_linux_x86_64.tar.gz | tar xz -C /kong/bin;
fi

# install rockspec, dependencies only
find /kong-plugin -maxdepth 1 -type f -name '*.rockspec' -exec luarocks install --only-deps {} \;
