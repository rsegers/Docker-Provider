mkdir -p $(Build.ArtifactStagingDirectory)/linux

echo "Installing NPM..."
sudo apt-get -y install npm

echo "Switching the directory..."
cd appmonitoring/ts/src
pwd
ls -a

echo "Installing npm packages..."
sudo npm install

#echo "Updating packages..."
#npm update

echo "Building the typescript project..."
tsc --build --force

if [ $? -ne 0 ]
then
    echo "Build failed"
    exit 1
fi

echo "Build is done"

echo "Running ESLint..."
npx eslint .

if [ $? -ne 0 ]
then
    echo "ESLint failed"
    exit 1
fi

echo "ESLint is done"

echo "Running Jest..."
npm test

if [ $? -ne 0 ]
then
    echo "Jest failed"
    exit 1
fi

echo "Jest is done"

pwd
ls -a

sudo apt-get update && sudo apt-get -y install qemu binfmt-support qemu-user-static
docker run --rm --privileged multiarch/qemu-user-static --reset -p yes

docker buildx create --name testbuilder
docker buildx use testbuilder

az --version
az account show
az account set -s ${{ variables.subscription }}
az acr login -n ${{ variables.containerRegistry }}

echo "Build reason = $(Build.Reason)"

if [ "$(Build.Reason)" != "PullRequest" ]; then
    docker buildx build --platform linux/amd64,linux/arm64 --tag ${{ variables.repoImageName }}:$(imageTag) -f ./Dockerfile --metadata-file $(Build.ArtifactStagingDirectory)/linux/metadata.json --push --provenance=false .

    docker pull ${{ variables.repoImageName }}:$(imageTag)
else
    docker buildx build --platform linux/amd64,linux/arm64 --tag ${{ variables.repoImageName }}:$(imageTag) -f ./Dockerfile --metadata-file $(Build.ArtifactStagingDirectory)/linux/metadata.json --provenance=false .

    # load the multi-arch image to run tests
    docker buildx build --tag ${{ variables.repoImageName }}:$(imageTag) -f ./Dockerfile --metadata-file $(Build.ArtifactStagingDirectory)/linux/metadata.json --load --provenance=false .
fi

curl -sfL https://raw.githubusercontent.com/aquasecurity/trivy/main/contrib/install.sh | sh -s -- -b /usr/local/bin

echo ".trivyignore file:"
cat .trivyignore

trivy image --ignore-unfixed --format json --no-progress --severity HIGH,CRITICAL,MEDIUM --exit-code 1 ${{ variables.repoImageName }}:$(imageTag)