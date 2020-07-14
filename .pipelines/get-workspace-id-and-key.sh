#!/bin/bash

echo "start: get workspace id and key from WorkspaceResourceId etc.."
for ARGUMENT in "$@"
do
   KEY=$(echo $ARGUMENT | cut -f1 -d=)
   VALUE=$(echo $ARGUMENT | cut -f2 -d=)

   case "$KEY" in
           WorkspaceResourceId) WorkspaceResourceId=$VALUE ;;

           *)
    esac
done

echo "Log Analytics Workspace ResourceId: ${WorkspaceResourceId}"

echo "getting workspace Guid"
workspaceGuid=$(az resource show --ids $WorkspaceResourceId --resource-type Microsoft.OperationalInsights/workspaces --query properties.customerId -o tsv)
echo "writing workspace guid to WSID file"
echo $workspaceGuid > ~/WSID

echo "getting workspace primaryshared key"
workspaceKey=$(az rest --method post --uri $WorkspaceResourceId/sharedKeys?api-version=2015-11-01-preview --query primarySharedKey -o tsv)
echo "writing workspace key to WSKEY file"
echo $workspaceKey > ~/WSKEY

echo "end: get workspace id and key from WorkspaceResourceId etc.."
