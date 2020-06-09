#!/bin/bash
# Install following build pre-requisites for the Linux Agent
# 1. install go lang and set the required environment variables
# 2. install build dependencies
# 3. install the docker engine
set -e
TEMP_DIR=temp-$RANDOM
install_go_lang()
{
  echo "installing go 1.14.1 version ..."
  sudo curl -O https://dl.google.com/go/go1.14.1.linux-amd64.tar.gz
  sudo tar -xvf go1.14.1.linux-amd64.tar.gz
  sudo mv go /usr/local
  echo "setting PATH and GOBIN environment variables"
  export PATH=$PATH:/usr/local/go/bin
  export GOBIN=/usr/local/go/bin
  echo "export PATH=$PATH:/usr/local/go/bin" >> ~/.bashrc
  echo "export GOBIN=/usr/local/go/bin" >> ~/.bashrc
  source ~/.bashrc
  echo "installation of go 1.14.1 and setting of PATH and GOBIN environment variables completed."
}

install_build_dependencies()
{
  echo "installing build dependencies"
  sudo apt-get upgrade -y
  sudo apt-get update -y
  sudo apt-get install git g++ make pkg-config libssl-dev libpam0g-dev rpm librpm-dev uuid-dev libkrb5-dev -y
  echo "installation of build depencies done."
}

install_docker()
{
 echo "installing docker"
 sudo apt-get update -y
 sudo apt-get install apt-transport-https ca-certificates curl gnupg-agent software-properties-common -y
 curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
 sudo apt-key fingerprint 0EBFCD88
 sudo add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
 sudo apt-get update -y
 sudo apt-get install docker-ce docker-ce-cli containerd.io -y
 # Allow your user to access the Docker CLI without needing root access.
 sudo usermod -aG docker $USER
 echo "installing docker completed"
}

install_python()
{
  echo "installing python ..."
  sudo apt-get update -y
  sudo apt-get install python -y
  echo "installation of python completed."
}

echo "installing build pre-requisites python, go 1.14.1, build dependencies and docker for the Linux Agent ..."
cd ~
echo "creating temp directory":$TEMP_DIR
sudo mkdir $TEMP_DIR && cd $TEMP_DIR

# install python
install_python

# install go
install_go_lang

# install build dependencies
install_build_dependencies

# install docker
install_docker

# if its running on wsl/2, set DOCKER_HOST env to use docker for desktop docker endpoint on the windows host
if [[ $(uname -r) =~ Microsoft$ ]]; then
    echo "****detected running on WSL/2 hence configuring remote docker daemon****"
    echo "export DOCKER_HOST=tcp://localhost:2375" >> ~/.bashrc && source ~/.bashrc
    echo "Make sure Docker Desktop for Windows running in Linux Containers mode and has Expose daemon on tcp://localhost:2375 without TLS enabled"
fi

echo "cleanup temp directory":$TEMP_DIR
cd ~
sudo rm -rf $TEMP_DIR
echo "installing build pre-requisites python, go 1.14.1, build dependencies and docker completed"