# About

This repository contains source code for Azure Monitor for containers Linux and Windows Agent

# Questions?

Feel free to contact engineering team owners in case you have any questions about this repository or project.

# Prerequisites

## Common
1. [Visual Studio Code](https://code.visualstudio.com/) for authoring
2. [Go lang](https://golang.org/) for building go code. Go lang version 1.14.1.
3. [Azure CLI](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli?view=azure-cli-latest) for Azure related operations

## Linux
4. Ubuntu 14.04 or higher to build Linux Agent. you can also use [WSL2](https://docs.microsoft.com/en-us/windows/wsl/install-win10).
  > Note: If you are using WSL2, make sure you have cloned the code into ubuntu not on to windows
5. [Docker](https://docs.docker.com/engine/install/ubuntu/) to build the docker image for Linux Agent

## Windows
6. Windows 10 Professional machine to build  Windows Agent
7. [Dokcer for Windows](https://docs.docker.com/docker-for-windows/) to build docker image for Windows Agent
8. [.NET Core SDK](https://dotnet.microsoft.com/download) to build the Windows Agent code
9. [gcc for windows](https://github.com/jmeubank/tdm-gcc/releases/download/v9.2.0-tdm64-1/tdm64-gcc-9.2.0.exe) to build go code


# Repo structure

The general directory structure is:

```
├── build/                                    - files to related to  compile and build the code
│   ├── version                               - build version used for docker prvider and go shared object(so) files
│   ├── common/                               - common to both windows and linux installers
│   │   ├── installer                         - files related to installer
|   |   |   |── scripts/                      - script files related to configmap parsing
│   ├── linux/                                - Makefile and installer files for the Docker Provider
│   │   ├── Makefile                          - Makefile to build the docker provider
│   │   ├── installer                         - files related to installer
|   |   |   |── bundle/                       - shell scripts to create shell bundle
|   |   |   |── conf/                         - plugin configuration files
|   |   |   |── datafiles/                    - data files for the installer
|   |   |   |── scripts/                      - script files related to livenessproble, tomlparser etc..
|   |   |   |── InstallBuilder/               - python script files for the install builder
│   ├── windows/                              - scripts to build the .net and go code
|   |   |── Makefile.ps1                      - powershell script to build .net and go lang code and copy the files to omsagentwindows directory
│   │   ├── installer                         - files related to installer
|   |   |   |── conf/                         - fluent, fluentbit and out_oms plugin configuration files
|   |   |   |── scripts/                      - script files related to livenessproble, filesystemwatcher, keepCertificateAlive etc..
|   |   |   |── certificategenerator/         - .NET code for the generation self-signed certificate of the windows agent
├── alerts/                                   - alert queries
├── kubernetes/                               - files related to Linux and Windows Agent for Kubernetes
│   ├── linux/                                - scripts to build the Docker image for Linux Agent
│   │   ├── DockerFile                        - DockerFile for Linux Agent Container Image
│   │   ├── main.sh                           - Linux Agent container entry point
│   │   ├── setup.sh                          - setup file for Linux Agent Container Image
│   │   ├── acrworkflows/                     - acr work flows for the Linux Agent container image
│   │   ├── defaultpromenvvariables           - default environment variables for Prometheus scraping
│   │   ├── defaultpromenvvariables-rs        - cluster level default environment variables for Prometheus scraping
│   ├── windows/                              - scripts to build the Docker image for Windows Agent
│   │   ├── acrworkflows/                     - acr work flows for the Windows Agent container image
│   │   ├── baseimage/                        - windowsservercore base image for the windows agent container
│   │   ├── DockerFile                        - DockerFile for Windows Agent Container Image
│   │   ├── main.ps1                          - Windows Agent container entry point
│   │   ├── setup.ps1                         - setup file for Windows Agent Container Image
│   ├── omsagent.yaml                         - kubernetes yaml for both Linux and Windows Agent
│   ├── container-azm-ms-agentconfig.yaml     - kubernetes yaml for agent configuration
├── scripts/                                  - scripts for onboarding, troubleshooting and preview scripts related to Azure Monitor for containers
│   ├── troubleshoot/                         - scripts for troubleshooting of Azure Monitor for containers onboarding issues
│   ├── onboarding/                           - scripts related to Azure Monitor for containers onboarding.
│   ├── preview/                              - scripts related to preview features ...
│   ├── build/                                - scripts related to build such as installing pre-requisites etc.
│   ├── deployment/                           - scripts related to deployment goes here.
│   ├── release/                              - scripts related to release  goes here.
├── source/                                   - source code
│   ├── plugins/                              - plugins source code
│   │   ├── go/                               - out_oms plugin code in go lang
│   │   ├── ruby/                             - plugins code in ruby
│   │   |   ├── health/                       - code for health feature
│   │   |   ├── lib/                          - lib for app insights ruby and this code of application_insights gem
│   │   |   ...                               - plugins in, out and filters code in ruby
│   ├── toml-parser/                          - code for parsing of toml configuration files
├── test/                                     - source code for tests
│   ├── unit-tests/                           - unit tests code
│   ├── scenario/                             - scenario tests code
├── !_README.md                               - this file
├── .gitignore                                - git config file with include/exclude file rules
├── LICENSE                                   - License file
├── Rakefile                                  - Rake file to trigger ruby plugin tests
└── ReleaseNotes.md                           - Release notes for the release of the Azure Monitor for containers agent
```

# Branches

- `ci_prod` branch contains codebase currently in production (or being prepared for release).
- `ci_dev` branch contains version in development.

To contribute: create your private branch off of `ci_dev`, make changes and use pull request to merge back to `ci_dev`.
Pull request must be approved by at least one engineering team members.

# Authoring code

We recommend using [Visual Studio Code](https://code.visualstudio.com/) for authoring.


# Building code

## Linux Agent

### Install Pre-requisites

1. Install go1.14.1, build dependencies and docker if you dont have installed already on your dev machine
```
bash ~/Docker-Provider/scripts/build/install-build-pre-requisites.sh
```
2. Verify python, docker and golang installed properly and also PATH and GOBIN environment variables set with go path.
   For some reason go env not set, run the following commands to set them
   ```
   export PATH=$PATH:/usr/local/go/bin
   export GOBIN=/usr/local/go/bin
   ```
3. If you want to use Docker on the WSL/2, verify following configuration settings configured
   ```
   echo $DOCKER_HOST
   # if either DOCKER_HOST not set already or doesnt have tcp://localhost:2375 value, set DOCKER_HOST value via this command
   echo "export DOCKER_HOST=tcp://localhost:2375" >> ~/.bashrc && source ~/.bashrc
   # on Docker Desktop for Windows make sure docker running linux mode and enabled Expose daemon on tcp://localhost:2375 without TLS
   ```

### Build Docker Provider Shell Bundle

1. Build the code  with below commands
```
cd ~/Docker-Provider/build/linux
make
```
If build successful, you should see docker-cimprov-x.x.x-x.universal.x86_64.sh under ~/Docker-Provider/target/Linux_ULINUX_1.0_x64_64_Release/
  > Note: x.x.x-x is the version of the docker provider which is determined from version info in version file

### Build Docker Image

1.  Navigate to below directory to build the docker image
  ```
  cd ~/Docker-Provider/kubernetes/linux/
  ```
2. Upload docker-cimprov-x.x.x-x.universal.x86_64.sh from ~/Docker-Provider/target/Linux_ULINUX_1.0_x64_64_Release/ to azure blob storage account blob

 ```
 AZURE_SUBSCRIPTIONID=<azure-subscription-id> # subscriptionId for the azure storage account (new or exist)
 STORAGE_ACCOUNT_RG=<resource-group>
 STORAGE_ACCOUNT_LOCATION=<location>
 STORAGE_ACCOUNT_NAME=<account-name>
 STORAGE_ACCOUNT_BLOB_NAME=<blob-name> # for example agentshellbundle

 # login to azure interactively and set the subscription id
 az login --use-device-code
 az account set -s $AZURE_SUBSCRIPTIONID

 # create rg and storage account if this doesnt exist one already
 az group create -n $STORAGE_ACCOUNT_RG -l $STORAGE_ACCOUNT_LOCATION
 az storage account create -n $STORAGE_ACCOUNT_NAME -g $STORAGE_ACCOUNT_RG -l $STORAGE_ACCOUNT_LOCATION

 # create blob container
 az storage container create --account-name $STORAGE_ACCOUNT_NAME --name $STORAGE_ACCOUNT_BLOB_NAME --auth-mode login --public-access container

 # upload docker-cimprov shell bundle to storage account. please specify the correct version
 az storage blob upload --account-name $STORAGE_ACCOUNT_NAME --container-name $STORAGE_ACCOUNT_BLOB_NAME --name docker-cimprov-10.0.0-0.universal.x86_64.sh --file  ~/Docker-Provider/target/Linux_ULINUX_1.0_x64_64_Release/docker-cimprov-10.0.0-0.universal.x86_64.sh
 # replace the placeholders in this url
 https://$STORAGE_ACCOUNT_NAME.blob.core.windows.net/$STORAGE_ACCOUNT_BLOB_NAME/docker-cimprov-10.0.0-0.universal.x86_64.sh

 # verify this url valid and exist by running the curl --head command as below
 curl --head https://mydevomsagentsa.blob.core.windows.net/agentshellbundle/docker-cimprov-10.0.0-0.universal.x86_64.sh
 ```
  > Note: x.x.x-x is the version of the docker provider which is determined from version info in docker.version file
3. Update the azure storage blob location of docker-cimprov-x.x.x-x.universal.x86_64.sh in setup.sh
 ```
 # update the setup.sh in this with the url in above step in place of  https://github.com/microsoft/Docker-Provider/releases/download/..
 cd ~/Docker-Provider/kubernetes/linux/
 ```
4. Update AGENT_VERSION environment variable with your imagetag in ~/Docker-Provider/kubernetes/linux/Dockerfile
 > Note: format of the imagetag will be ci<release>MMDDYYYY. possible values for release are test, dev, preview, dogfood, prod etc.
5. Build the Docker image via below command
```
   docker build -t  <repo>/<imagename>:<imagetag> .
```
6. Push the Docker image to docker repo
```
   docker push  <repo>/<imagename>:<imagetag>
```

## Windows Agent
> Note: To build the Windows Agent Image, you will need Windows 10 Pro or higher machine with Docker for Windows
### Install Pre-requisites
1. Install .Net Core SDK 2.2 or higher from https://dotnet.microsoft.com/download if you dont have installed already
2. Install go1.14.1 if you havent installed already
  ```
  cd  %userprofile%
  mkdir go
  cd  %userprofile%\go
  curl -LO https://dl.google.com/go/go1.14.1.windows-amd64.msi
  # install go. default will get installed %SYSTEMDRIVE%\go
  msiexec /i %userprofile%\go\go1.14.1.windows-amd64.msi
  ```
3. Install build dependencies
```
cd  %userprofile%
mkdir gcctemp && cd gcctemp
## download gcc for windows
curl -LO https://github.com/jmeubank/tdm-gcc/releases/download/v9.2.0-tdm64-1/tdm64-gcc-9.2.0.exe
## install gcc on windows
%userprofile%\gcctemp\tdm64-gcc-9.2.0.exe
```
4. Install Docker for windows https://docs.docker.com/docker-for-windows/install/

### Build Certificate Generator Source code and Out OMS Go plugin code
1. Build Certificate generator source code in .NET and Out OMS Plugin code in Go lang  by running these commands in CMD shell
```
cd %userprofile%\Docker-Provider\build\windows # based on your repo path
powershell -executionpolicy bypass -File .\Makefile.ps1 # trigger build and publish
```
### Build Docker Image

1. Update AGENT_VERSION environment variable with your intended imagetag in  %userprofile%\Docker-Provider\kubernetes\windows\Dockerfile
 > Note: format of the imagetag will be win-ci<release>MMDDYYYY. possible values for release are test, dev, preview, dogfood, prod etc.

2.  Navigate to below directory to build the docker image
```
  cd %userprofile%\Docker-Provider\kubernetes\windows # based on your repo path
  docker build -t  <repo>/<imagename>:win-<imagetag> .

```
3. Push the Docker image to docker repo. For testing, you will be pushing to Docker hub
```
  cd %userprofile%\Docker-Provider\kubernetes\windows # based on your repo path
  docker push  <repo>/<imagename>:<imagetag>
```

# Update Kubernetes yamls

Navigate to Kubernetes directory and update the yamls with latest docker image of Linux and Windows Agent and other relevant updates.

#  Deployment and Validation

Deploy the Kubernetes yamls on to your Kubernetes cluster with Linux and Windows nodes and make sure all the scenarios works.

# E2E Tests
TBD

# Code of Conduct

This project has adopted the [Microsoft Open Source Code of Conduct] (https://opensource.microsoft.com/codeofconduct/). For more information see the [Code of Conduct FAQ] (https://opensource.microsoft.com/codeofconduct/faq/) or contact opencode@microsoft.com with any additional questions or comments.

