#!/bin/bash

# Name of the secret and the namespace
secret_name=app-monitoring-webhook-cert
namespace=kube-system

# Get the secret
secret=$(kubectl get secret $secret_name --namespace=$namespace -o json)

# Decode each key in the secret and check if it's a valid certificate
caCert=$(jq -r '.data."ca.cert"' <<< $secret |  base64 --decode)
tlsCert=$(jq -r '.data."tls.cert"' <<< $secret |  base64 --decode)
tlsKey=$(jq -r '.data."tls.key"' <<< $secret |  base64 --decode)


if [[ "$caCert" =~ "-----BEGIN CERTIFICATE-----" ]] && [[ "$caCert" =~ "-----END CERTIFICATE-----" ]]; then
    echo "ca.cert exists and is in the format of a certificate."
else
    echo "ca.cert exists but is NOT in the format of a certificate."
fi

if [[ "$tlsCert" =~ "-----BEGIN CERTIFICATE-----" ]] && [[ "$tlsCert" =~ "-----END CERTIFICATE-----" ]]; then
    echo "tls.cert exists and is in the format of a certificate."
else
    echo "tls.cert exists but is NOT in the format of a certificate."
fi

if [[ "$tlsKey" =~ "-----BEGIN RSA PRIVATE KEY-----" ]] && [[ "$tlsKey" =~ "-----END RSA PRIVATE KEY-----" ]]; then
    echo "tls.key exists and is in the format of a private key."
else
    echo "tls.key exists but is NOT in the format of a private key."
fi



