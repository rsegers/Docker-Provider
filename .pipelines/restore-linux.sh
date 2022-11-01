#!/bin/bash
pwd
PWD=`pwd`
pushd $PWD

# Find location of this script
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
echo $DIR

# change to source code directory
cd $DIR/../source/plugins/go/src
pwd

echo "go environment variables"
go env

echo "start:get go modules"
go get
echo "end:get go modules"

# Restore working directory
popd

# Exit with explicit 0 exit code so build will not fail
exit 0
