#!/bin/bash
# oras[https://github.com/deislabs/oras)] required to push an HELM chart as an OCI artifact

echo "start: installing oras tool"
DEFAULT_ORAS_VERSION="0.8.1"
for ARGUMENT in "$@"
do
   KEY=$(echo $ARGUMENT | cut -f1 -d=)
   VALUE=$(echo $ARGUMENT | cut -f2 -d=)

   case "$KEY" in
           ORAS_VERSION) ORAS_VERSION=$VALUE ;;
           *)
    esac
done

if [ -z $ORAS_VERSION ]; then
   ORAS_VERSION=$DEFAULT_ORAS_VERSION
fi

echo "oras version: ${ORAS_VERSION}"

echo "start: downloading oras tool"
curl -LO https://github.com/deislabs/oras/releases/download/v${ORAS_VERSION}/oras_${ORAS_VERSION}_linux_amd64.tar.gz
echo "end: downloading oras tool"

echo "start: extract oras tar file"
mkdir -p oras-install/
tar -zxf oras_${ORAS_VERSION}_*.tar.gz -C oras-install/
echo "end: extract oras tar file"

echo "start: move oras binaries to /usr/local/bin/"
mv oras-install/oras /usr/local/bin/
echo "end: move oras binaries to /usr/local/bin/"

rm -rf oras_${ORAS_VERSION}_*.tar.gz oras-install/

echo "end: installing oras tool"
