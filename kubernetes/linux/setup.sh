#!/bin/bash

TMPDIR="/opt"
cd $TMPDIR

if [ -z $1 ]; then
    ARCH="amd64"
else
    ARCH=$1
fi

sudo tdnf install ca-certificates-microsoft -y
sudo update-ca-trust

# sudo tdnf install ruby-3.1.3 -y
# # remove unused default gem openssl, find as they have some known vulns
# rm /usr/lib/ruby/gems/3.1.0/specifications/default/openssl-3.0.1.gemspec
# rm -rf /usr/lib/ruby/gems/3.1.0/gems/openssl-3.0.1
# rm /usr/lib/ruby/gems/3.1.0/specifications/default/find-0.1.1.gemspec
# rm -rf /usr/lib/ruby/gems/3.1.0/gems/find-0.1.1

tdnf install which procps-ng -y
curl -sSL https://rvm.io/mpapis.asc | gpg --import -
curl -sSL https://rvm.io/pkuczynski.asc | gpg --import -
curl -sSL https://get.rvm.io | bash -s stable

# setup paths for ruby and rvm
if [ -f /etc/profile.d/rvm.sh ]; then
    source /etc/profile.d/rvm.sh
    echo "[ -f /etc/profile.d/rvm.sh ] && source /etc/profile.d/rvm.sh" >> ~/.bashrc
fi

rvm install ruby-3.1.3
rvm --default use 3.1.3
# remove unused default gem openssl, find and rvm as they have some known vulns
rm /usr/local/rvm/rubies/ruby-3.1.3/lib/ruby/gems/3.1.0/specifications/default/openssl-3.0.1.gemspec
rm /usr/local/rvm/rubies/ruby-3.1.3/lib/ruby/gems/3.1.0/specifications/default/find-0.1.1.gemspec
rm /usr/local/rvm/rubies/ruby-3.1.3/lib/ruby/gems/3.1.0/specifications/rvm-1.11.3.9.gemspec


if [ "${ARCH}" != "arm64" ]; then
    wget "https://github.com/microsoft/Docker-Provider/releases/download/official%2Fmdsd%2F1.17.1%2Frpm/azure-mdsd_1.17.1-build.master.377_x86_64.rpm" -O azure-mdsd.rpm
else
    wget "https://github.com/microsoft/Docker-Provider/releases/download/official%2Fmdsd%2F1.17.1%2Frpm/azure-mdsd_1.17.1-build.master.377_aarch64.rpm" -O azure-mdsd.rpm
fi
sudo tdnf install -y azure-mdsd.rpm
cp -f $TMPDIR/mdsd.xml /etc/mdsd.d
cp -f $TMPDIR/envmdsd /etc/mdsd.d
rm /usr/sbin/telegraf
rm azure-mdsd.rpm

mdsd_version=$(sudo tdnf list installed | grep mdsd | awk '{print $2}')
echo "Azure mdsd: $mdsd_version" >> packages_version.txt

# log rotate conf for mdsd and can be extended for other log files as well
cp -f $TMPDIR/logrotate.conf /etc/logrotate.d/ci-agent

#download inotify tools for watching configmap changes
sudo tdnf check-update -y
sudo tdnf install inotify-tools -y

#used to parse response of kubelet apis
#ref: https://packages.ubuntu.com/search?keywords=jq
sudo tdnf install jq-1.6-1.cm2 -y

#used to setcaps for ruby process to read /proc/env
sudo tdnf install libcap -y

sudo tdnf install telegraf-1.25.2 -y
telegraf_version=$(sudo tdnf list installed | grep telegraf | awk '{print $2}')
echo "telegraf $telegraf_version" >> packages_version.txt
mv /usr/bin/telegraf /opt/telegraf

# Use wildcard version so that it doesnt require to touch this file
/$TMPDIR/docker-cimprov-*.*.*-*.*.sh --install
docker_cimprov_version=$(sudo tdnf list installed | grep docker-cimprov | awk '{print $2}')
echo "DOCKER_CIMPROV_VERSION=$docker_cimprov_version" >> packages_version.txt

#install fluent-bit
sudo tdnf install fluent-bit-2.0.9 -y
echo "$(fluent-bit --version)" >> packages_version.txt

# install fluentd using the mariner package
# sudo tdnf install rubygem-fluentd-1.14.6 -y
gem install fluentd -v "1.14.6" --no-document
echo "$(fluentd --version)" >> packages_version.txt
fluentd --setup ./fluent

gem install gyoku iso8601 bigdecimal --no-doc
gem install tomlrb -v "2.0.1" --no-document


rm -f $TMPDIR/docker-cimprov*.sh
rm -f $TMPDIR/mdsd.xml
rm -f $TMPDIR/envmdsd

# Remove settings for cron.daily that conflict with the node's cron.daily. Since both are trying to rotate the same files
# in /var/log at the same time, the rotation doesn't happen correctly and then the *.1 file is forever logged to.
rm /etc/logrotate.d/azure-mdsd
