#!/bin/sh
countErr=$(grep -iF  "socket_writer" /var/opt/microsoft/docker-cimprov/log/telegraf.log | wc -l | tr -d '\n')
echo "telegraf,Source=telegrafErrLog telegrafTCPWriteErrorCountTotal=${countErr}i"