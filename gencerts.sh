#!/bin/bash
set -x

# Create CA certificate
openssl genrsa 2048 > ca-key.pem
openssl req -new -x509 -nodes -days 3600 -key ca-key.pem -out ca.pem -subj "<your-company>"

# Create server certificate, remove passphrase, and sign it
# server-cert.pem = public key, server-key.pem = private key
openssl req -newkey rsa:2048 -days 3600 -nodes -keyout server-key.pem -out server-req.pem -subj "<your-company>"
openssl rsa -in server-key.pem -out server-key.pem
openssl x509 -req -in server-req.pem -days 3600 -CA ca.pem -CAkey ca-key.pem -set_serial 01 -out server-cert.pem

# Create client certificate, remove passphrase, and sign it
# client-cert.pem = public key, client-key.pem = private key
openssl req -newkey rsa:2048 -days 3600 -nodes -keyout client-key.pem -out client-req.pem -subj "<your-company>"
openssl rsa -in client-key.pem -out client-key.pem
openssl x509 -req -in client-req.pem -days 3600 -CA ca.pem -CAkey ca-key.pem -set_serial 01 -out client-cert.pem

# Verify Certs
openssl verify -CAfile ca.pem server-cert.pem client-cert.pem

# list contents of Certs
# OPTIONAL - list contents of CERTS
openssl x509 -text -in ca.pem|grep CN
openssl x509 -text -in server-cert.pem|grep CN
openssl x509 -text -in client-cert.pem|grep CN

# Change ownership of pem files & permissions to 400
chown -R mysql:mysql /etc/ssl/*.pem
chmod 400 /etc/ssl/*.pem
chown -R mysql:mysql /etc/ssl

# OPTIONAL - list contents of CERTS
openssl x509 -text -in ca.pem
openssl x509 -text -in server-cert.pem
openssl x509 -text -in client-cert.pem

exit 0

