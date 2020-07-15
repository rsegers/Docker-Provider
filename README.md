# Private Preview Instructions
Intended for those looking to use an integrated version of the Container Insights agent and OpenTelemetry collector to obtain both infrastructure and application insights. If you are currently not set up to use the Container Insights agent, please follow the original steps listed below the divider (starting from "About"), and return to these instructions upon completion. This integration is currently only available with the Linux Agent.

## Build collector binaries
```
cd ~/Docker-Provider/build/linux
make OT_COLLECTOR_ENABLE=1
```
Check if build was successful by confirming `otelcontribcol_linux_amd64` exists after running:
```
ls ../../kubernetes/otel-collector/
```

## Deploy collector
Add the repo and confirm it's been added by checking `open-telemetry` is listed.
```
helm repo add open-telemetry https://ayusheesingh.github.io/helm-chart/
helm repo list 
```
Retrieve your Azure credentials by going to Azure Portal > your cluster > Properties tab. Replace the designated `<>` fields with your information, and install the helm chart:
```
helm upgrade --install azmon-containers-release-1-ot --set omsagent.instrumentationKey=<your_instrumentation_key>,omsagent.secret.wsid=<your_wsid>,omsagent.secret.key=<your_key>,omsagent.env.clusterName=<your_cluster_name>  open-telemetry/azuremonitor-containers
kubectl get deployments 
```
Confirm `otel-collector` is running. 

## Run your application 
Make sure your app that is being instrumented with OpenTelemetry is configured to use `endpoint="otel-collector:55678"`.

Run your application, and see your traces in Application Insights. If you run into issues, feel free to reach out to t-aysi@microsoft.com, or visit the instructions for a sample Python application in `source/opentelemetry-collector-contrib/examples/tracing` and make sure that it works as expected.
___
# About

This repository contains source code for Azure Monitor for containers Linux and Windows Agent

# Questions?

Feel free to contact engineering team owners in case you have any questions about this repository or project.

# Prerequisites

## Common
- [Visual Studio Code](https://code.visualstudio.com/) for authoring
- [Go lang](https://golang.org/) for building go code. Go lang version 1.14.1.

> Note: If you are using WSL2, make sure you have cloned the code onto ubuntu not onto windows

## WSL2
- [WSL2](https://docs.microsoft.com/en-us/windows/wsl/install-win10).
- configure [Docker-for-windows-wsl2](https://docs.docker.com/docker-for-windows/wsl/)

## Linux
- Ubuntu 14.04 or higher to build Linux Agent.
- [Docker](https://docs.docker.com/engine/install/ubuntu/) to build the docker image for Linux Agent
> Note: if you are using WSL2, you can ignore Docker since Docker for windows will be used.

## Windows
- Windows 10 Professional machine to build  Windows Agent
- [Dokcer for Windows](https://docs.docker.com/docker-for-windows/) to build docker image for Windows Agent
- [.NET Core SDK](https://dotnet.microsoft.com/download) to build the Windows Agent code
- [gcc for windows](https://github.com/jmeubank/tdm-gcc/releases/download/v9.2.0-tdm64-1/tdm64-gcc-9.2.0.exe) to build go code


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

We recommend using [Visual Studio Code](https://code.visualstudio.com/) for authoring. Windows 10 with Ubuntu App can be used for both Windows and Linux  Agent development and recommened to clone the code onto Ubuntu app so that you dont need to worry about line ending issues LF vs CRLF.

# Building code

## Linux Agent

### Install Pre-requisites

1. Install go1.14.1, dotnet, powershell, docker and build dependencies to build go code for both Linux and Windows platforms
```
bash ~/Docker-Provider/scripts/build/linux/install-build-pre-requisites.sh
```
2. Verify python, docker and golang installed properly and also PATH and GOBIN environment variables set with go bin path.
   For some reason go env not set by install-build-pre-requisites.sh script, run the following commands to set them
   ```
   export PATH=$PATH:/usr/local/go/bin
   export GOBIN=/usr/local/go/bin
   ```
3. If you want to use Docker on the WSL2, verify following configuration settings configured on your Ubuntu app
   ```
   echo $DOCKER_HOST
   # if either DOCKER_HOST not set already or doesnt have tcp://localhost:2375 value, set DOCKER_HOST value via this command
   echo "export DOCKER_HOST=tcp://localhost:2375" >> ~/.bashrc && source ~/.bashrc
   # on Docker Desktop for Windows make sure docker running linux mode and enabled Expose daemon on tcp://localhost:2375 without TLS
   ```

### Build Docker Provider Shell Bundle and Docker Image and Publish Docker Image

> Note: If you are using WSL2, ensure Docker for windows running Linux containers mode to build Linux agent image successfully

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
docker build -t <repo>/<imagename>:<imagetag> --build-arg IMAGE_TAG=<imagetag> .
docker push <repo>/<imagename>:<imagetag>
```
## Windows Agent

### Install Pre-requisites

If you are planning to build the .net and go code for windows agent on Linux machine and you have already have Docker for Windows on Windows machine, then you may skip this.

```
powershell # launch powershell with elevated admin on your windows machine
Set-ExecutionPolicy -ExecutionPolicy bypass # set the execution policy
net use z: \\wsl$\Ubuntu-16.04 # map the network drive of the ubuntu app to windows
cd z:\home\sshadmin\Docker-Provider\scripts\build\windows # based on your repo path
.\install-build-pre-requisites.ps1 #
```
#### Build Certificate Generator Source code and Out OMS Go plugin code

> Note: .net and go code for windows agent can built on Ubuntu

```
cd ~/Docker-Provider/build/windows # based on your repo path on ubuntu or WSL2
pwsh #switch to powershell
.\Makefile.ps1 # trigger build and publish of .net and go code
```
> Note: format of the imagetag will be `win-ci<release><MMDDYYYY>`. possible values for release are test, dev, preview, dogfood, prod etc.

####  Build and Push Docker Image

> Note: windows container can only built on windows hence you will have to execute below commands on windows via accessing network share or copying published bits omsagentwindows under kubernetes directory on to windows machine

```
net use z: \\wsl$\Ubuntu-16.04 # map the network drive of the ubuntu app to windows
cd z:\home\sshadmin\Docker-Provider\kubernetes\windows # based on your repo path
docker build -t <repo>/<imagename>:<imagetag> --build-arg IMAGE_TAG=<imagetag> .
docker push <repo>/<imagename>:<imagetag>
```

### Build Cert generator, Out OMS Plugun and Docker Image and Publish Docker Image

If you have code cloned on to windows, you can built everything for windows agent on windows machine via below instructions

```
cd %userprofile%\Docker-Provider\kubernetes\windows\dockerbuild # based on your repo path
docker login # if you want to publish the image to acr then login to acr via `docker login <acr-name>`
powershell -ExecutionPolicy bypass  # switch to powershell if you are not on powershell already
.\build-and-publish-docker-image.ps1 -image <repo>/<imagename>:<imagetag> # trigger build code and image and publish docker hub or acr
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

This project has adopted the [Microsoft Open Source Code of Conduct] (https://opensource.microsoft.com/codeofconduct/).
For more information see the [Code of Conduct FAQ] (https://opensource.microsoft.com/codeofconduct/faq/) or contact opencode@microsoft.com with any additional questions or comments.

