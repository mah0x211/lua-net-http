#!/bin/sh

#
# generate private key
#
openssl genrsa 2048 > cert/cert.key

#
# generate cert sign request
#
openssl req -new -key cert/cert.key <<EOF > cert/cert.csr
JP
Tokyo



127.0.0.1



EOF

#
# generate cert
#
openssl x509 -days 365 -req -signkey cert/cert.key < cert/cert.csr > cert/cert.crt
