#!/bin/sh

#
# generate private key
#
openssl genrsa 2048 > cert/server.key

#
# generate cert sign request
#
openssl req -new -key cert/server.key <<EOF > cert/server.csr
JP
Tokyo



127.0.0.1



EOF

#
# generate cert
#
openssl x509 -days 365 -req -signkey cert/server.key < cert/server.csr > cert/server.crt
