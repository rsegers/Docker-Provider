#!/bin/sh
countErr=$(grep -iF  "socket_writer" /var/opt/microsoft/docker-cimprov/log/telegraf.log | wc -l | tr -d '\n')
echo "telegraf,AKS_RESOURCE_ID=${AKS_RESOURCE_ID} telegrafTCPWriteErrorCountTotal=${countErr}i"