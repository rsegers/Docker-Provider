#!/bin/bash

echo "start: get kubeconfig from secret in KV"

for ARGUMENT in "$@"
do
   KEY=$(echo $ARGUMENT | cut -f1 -d=)
   VALUE=$(echo $ARGUMENT | cut -f2 -d=)

   case "$KEY" in
           KV) KV=$VALUE ;;
           KVSECRETNAMEKUBECONFIG) KubeConfigSecret=$VALUE ;;
           *)
    esac
done

echo "key vault name:${KV}"
echo "key vault secret name for kubeconfig:${KVSECRETNAMEKUBECONFIG}"

echo "downloading the KubeConfig from KV:${KV} and KV secret:${KubeConfigSecret}"
az keyvault secret download --file ~/kubeconfig --vault-name ${KV} --name ${KubeConfigSecret}
echo "downloaded the KubeConfig from KV:${KV} and KV secret:${KubeConfigSecret}"

echo "end: get kubeconfig from secret in KV"
