commit=$(git describe)
imageTag="$commit"
    
echo "imageTag is $imageTag"

echo "##vso[task.setvariable variable=imageTag;isOutput=true]$imageTag"

cd $(Build.SourcesDirectory)/deployment/mergebranch-webhook-deployment/ServiceGroupRoot/Scripts
tar -czvf ../artifacts.tar.gz pushWebhookToAcr.sh