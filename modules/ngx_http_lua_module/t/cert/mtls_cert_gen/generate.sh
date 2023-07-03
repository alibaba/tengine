#!/bin/bash

rm *.pem *.csr cfssl cfssljson

wget -O cfssl https://github.com/cloudflare/cfssl/releases/download/v1.6.1/cfssl_1.6.1_linux_amd64
wget -O cfssljson https://github.com/cloudflare/cfssl/releases/download/v1.6.1/cfssljson_1.6.1_linux_amd64
chmod +x cfssl cfssljson

./cfssl gencert -initca -config profile.json mtls_ca.json | ./cfssljson -bare mtls_ca

./cfssl gencert -ca mtls_ca.pem -ca-key mtls_ca-key.pem -config profile.json -profile=client mtls_client.json | ./cfssljson -bare mtls_client
./cfssl gencert -ca mtls_ca.pem -ca-key mtls_ca-key.pem -config profile.json -profile=server mtls_server.json | ./cfssljson -bare mtls_server

openssl x509 -in mtls_ca.pem -text > ../mtls_ca.crt
mv mtls_ca-key.pem ../mtls_ca.key

openssl x509 -in mtls_client.pem -text > ../mtls_client.crt
mv mtls_client-key.pem ../mtls_client.key

openssl x509 -in mtls_server.pem -text > ../mtls_server.crt
mv mtls_server-key.pem ../mtls_server.key

rm *.pem *.csr cfssl cfssljson
