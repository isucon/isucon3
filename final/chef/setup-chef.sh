#!/bin/sh -x

set -e
cd /tmp
yum -y install make gcc libyaml ruby ruby-libs ruby-rdoc ruby-irb ruby-devel patch
curl -O http://production.cf.rubygems.org/rubygems/rubygems-1.8.25.tgz
tar zxf rubygems-1.8.25.tgz
cd rubygems-1.8.25
ruby setup.rb --no-format-executable
gem install chef --no-ri --no-rdoc
