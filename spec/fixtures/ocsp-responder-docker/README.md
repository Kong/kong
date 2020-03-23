

```
# build image
docker build -t ocsp .

# run container
# in a seperate terminal
docker run -it --name=ocsp ocsp

# issue a client cert for foo@konghq.com
docker exec -it ocsp ash /create_client foo usr_cert

# get the cert for foo@konghq.com
docker exec -it ocsp ash /get_cert foo

# get the private key for foo@konghq.com
docker exec -it ocsp ash /get_key foo

# get the ca cert (add to kong ca_certificate)
docker exec -it ocsp ash /get_ca
```

The default OCSP responder is set to `http://127.0.0.1:2560`, if you test Kong in vagrant,
this might need to be changed. Open `intermediate-openssl.conf` and change `http://127.0.0.1:2560`
to `http://HOST:2560` (HOST is likely the VAGRANT_IP mask with 255.255.255.0 and last section being `2`).

The default CRL url is `http://127.0.0.1:8080/kong.crl`, you will need a webserver to actually serve
that file

```
# test revoke, the following will immediately effective in oscp responder
# it will also print the crl in pem format

docker exec -it ocsp ash /revoke_client foo

# to see the crl again

docker exec -it ocsp ash /get_crl

# convert into DER format (run on host), then copy kong.crl to webserver 127.0.0.1:8080

openssl crl -inform PEM -in crl.pem -outform DER -out kong.crl

```
