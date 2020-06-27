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

> Note: recommend to clone the code into Ubuntu app on Windows 10 so that you can work on development of both windows and linux agent.

# Repo structure

The general directory structure is:

```
├── .pipelines/                               - files related to azure devops ci and cd pipelines
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
│   │   ├── dockerbuild                       - script to build docker provider, docker image and publish docker image
│   │   ├── DockerFile                        - DockerFile for Linux Agent Container Image
│   │   ├── main.sh                           - Linux Agent container entry point
│   │   ├── setup.sh                          - setup file for Linux Agent Container Image
│   │   ├── acrworkflows/                     - acr work flows for the Linux Agent container image
│   │   ├── defaultpromenvvariables           - default environment variables for Prometheus scraping
│   │   ├── defaultpromenvvariables-rs        - cluster level default environment variables for Prometheus scraping
│   ├── windows/                              - scripts to build the Docker image for Windows Agent
│   │   ├── dockerbuild                       - script to build the code and docker imag, and publish docker image
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

We recommend using [Visual Studio Code](https://code.visualstudio.com/) for authoring. Windows 10 with Ubuntu App can be used for both Windows and Linux  Agent development and recommened to clone the code into Ubuntu app so that you dont need to wory about line ending issues LF vs CRLF.

# Building code

## Linux Agent

### Install Pre-requisites

1. Install go1.14.1, build dependencies and docker if you dont have installed already on your dev machine
```
bash ~/Docker-Provider/scripts/build/linux/install-build-pre-requisites.sh
```
2. Verify python, docker and golang installed properly and also PATH and GOBIN environment variables set with go path.
   For some reason go env not set by install-build-pre-requisites.sh script, run the following commands to set them
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

### Build Docker Provider Shell Bundle and Docker Image and Publish Docker Image

```
cd ~/Docker-Provider/kubernetes/linux/dockerbuild
sudo docker login # if you want to publish the image to acr then login to acr via `docker login <acr-name>`
# build provider, docker image and publish to docker image
bash build-and-publish-docker-image.sh --image <repo>/<imagename>:<imagetag>
```
> Note: format of the imagetag will be `ci<release><MMDDYYYY>`. possible values for release are test, dev, preview, dogfood, prod etc.

If you prefer to build docker provider shell bundle and image separately, then you can follow below instructions

##### Build Docker Provider shell bundle
```
cd ~/Docker-Provider/build/linux
make
```
##### Build and Push Docker Image
```
cd ~/Docker-Provider/kubernetes/linux/
docker build -t <repo>/<imagename>:<imagetag> IMAGE_TAG=<imagetag> .
docker push <repo>/<imagename>:<imagetag>
```

## Windows Agent
> Note: Below instructions are assumed you have cloned the code on to WSL/2 machine
### Install Pre-requisites
```
powershell # launch powershell with elevated admin on your windows machine
Set-ExecutionPolicy -ExecutionPolicy bypass # set the execution policy
net use z: \\wsl$\Ubuntu-16.04 # map the network drive of the ubuntu app to windows
cd z:\home\sshadmin\Docker-Provider\scripts\build\windows # based on your repo path
.\install-build-pre-requisites.ps1 #
```
### Build Cert generator, Out OMS Plugun and Docker Image and Publish Docker Image

Build Certificate generator source code in .NET and Out OMS Plugin code in Go lang  by running these commands in CMD shell
```
docker login # if you want to publish the image to acr then login to acr via `docker login <acr-name>`
cd z:\home\sshadmin\Docker-Provider\kubernetes\windows\dockerbuild # based on your repo path
powershell -ExecutionPolicy bypass  # switch to powershell if you are not on powershell already
.\build-and-publish-docker-image.ps1 -image <repo>/<imagename>:<imagetag> # trigger build code and image and publish docker hub or acr
```
> Note: format of the imagetag will be `ci<release><MMDDYYYY>`. possible values for release are test, dev, preview, dogfood, prod etc.

If you prefe to build Certificate Generator Source code and Out OMS Go plugin code and image separately, then you can follow below instructions

#### Build Certificate Generator Source code and Out OMS Go plugin code
```
cd z:\home\sshadmin\Docker-Provider\scripts\build\windows # based on your repo path
powershell -executionpolicy bypass -File .\Makefile.ps1 # trigger build and publish
```

####  Build and Push Docker Image
```
cd z:\home\sshadmin\Docker-Provider\kubernetes\windows # based on your repo path
docker build -t <repo>/<imagename>:<imagetag> IMAGE_TAG=<imagetag> .
docker push <repo>/<imagename>:<imagetag>
```

# Azure DevOps Build Pipeline

Navigate to https://github-private.visualstudio.com/microsoft/_build?view=pipelines to see Linux and Windows Agent build pipelines. These pipelines are configured with CI triggers for dev and master (TBD).

Docker Images will be pushed to CDPX ACR repos and these needs to retagged and pushed to corresponding ACR or docker hub. Only onboarded Azure AD AppId has permission to pull the images from CDPx ACRs.

Please reach out the agent engineering team if you need access to it.

## Onboarding feature branch

Here are the instructions to onboard the feature branch to Azure Dev Ops pipeline

 1. Navigate to https://github-private.visualstudio.com/microsoft/_apps/hub/azurecdp.cdpx-onboarding.cdpx-onboarding-tab
 2. Select the repository as "docker-provider" from repository drop down
 3. click on validate repository
 4. select the your feature branch from Branch drop down
 5. Select the Operation system as "Linux" and Build type as "buddy"
 6. create build definition
 7. enable continous integration on trigger on the build definition

 This will create build definition for the Linux agent.
 Repeat above steps except that this time select Operation system as "Windows" to onboard the pipeline for Windows agent.

# Update Kubernetes yamls

Navigate to Kubernetes directory and update the yamls with latest docker image of Linux and Windows Agent and other relevant updates.

#  Deployment and Validation

Deploy the Kubernetes yamls on to your Kubernetes cluster with Linux and Windows nodes and make sure all the scenarios works.

# E2E Tests
TBD

# Code of Conduct

This project has adopted the [Microsoft Open Source Code of Conduct] (https://opensource.microsoft.com/codeofconduct/). For more information see the [Code of Conduct FAQ] (https://opensource.microsoft.com/codeofconduct/faq/) or contact opencode@microsoft.com with any additional questions or comments.

