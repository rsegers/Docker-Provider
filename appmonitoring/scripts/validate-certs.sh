#!/bin/bash

# Name of the secret and the namespace
secret_name=app-monitoring-webhook-cert
mwhc_name=app-monitoring-webhook
namespace=kube-system

# Get the secret
secret=$(kubectl get secret $secret_name --namespace=$namespace -o json)

# Get the mwhc
mwhc=$(kubectl get mutatingwebhookconfiguration $mwhc_name -o json)

# Decode each key in the secret and check if it's a valid certificate
caCert_mwhc=$(jq -r '.webhooks[0].clientConfig.caBundle' <<< $mwhc |  base64 --decode)
caCert=$(jq -r '.data."ca.cert"' <<< $secret |  base64 --decode)

if [ "$caCert_mwhc" == "$caCert" ]; then
  echo "Success! Values for CA Certificate match in MWHC as well as secret store"
else
  echo "Values for CA Certificate do not match in MWHC and secret store. Something went wrong"
  exit 1
fi

tlsCert=$(jq -r '.data."tls.cert"' <<< $secret |  base64 --decode)
tlsKey=$(jq -r '.data."tls.key"' <<< $secret |  base64 --decode)


if [[ "$caCert" =~ "-----BEGIN CERTIFICATE-----" ]] && [[ "$caCert" =~ "-----END CERTIFICATE-----" ]]; then
    echo "Success! ca.cert exists and is in the format of a certificate."
else
    echo "ca.cert exists but is NOT in the format of a certificate."
fi

if [[ "$tlsCert" =~ "-----BEGIN CERTIFICATE-----" ]] && [[ "$tlsCert" =~ "-----END CERTIFICATE-----" ]]; then
    echo "Success! tls.cert exists and is in the format of a certificate."
else
    echo "tls.cert exists but is NOT in the format of a certificate."
fi

if [[ "$tlsKey" =~ "-----BEGIN RSA PRIVATE KEY-----" ]] && [[ "$tlsKey" =~ "-----END RSA PRIVATE KEY-----" ]]; then
    echo "Success! tls.key exists and is in the format of a private key."
else
    echo "tls.key exists but is NOT in the format of a private key."
fi



