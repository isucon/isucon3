#
# Cookbook Name:: common-packages
# Recipe:: default
#
# Copyright 2013, KAYAC Inc.
#
# 
#
package "yum-utils"

remote_file "/tmp/epel-release-6-8.noarch.rpm" do
  source "http://ftp.riken.jp/Linux/fedora/epel/6/i386/epel-release-6-8.noarch.rpm"
  not_if "rpm -q epel-release"
end

rpm_package "/tmp/epel-release-6-8.noarch.rpm" do
  action :install
  not_if "rpm -q epel-release"
end

bash "enable epel" do
  user "root"
  code "yum-config-manager --enable epel"
end

remote_file "/tmp/remi-release-6.rpm" do
  source "http://rpms.famillecollet.com/enterprise/remi-release-6.rpm"
  not_if "rpm -q remi-release"
end

rpm_package "/tmp/remi-release-6.rpm" do
  action :install
  not_if "rpm -q remi-release"
end

bash "enable remi" do
  user "root"
  code "yum-config-manager --enable remi && yum-config-manager --setopt='remi.priority=9' --save remi"
end

package "ImageMagick"
package "mercurial"
package "openssl-devel"
package "readline-devel"
package "sqlite-devel"
package "bzip2-devel"
package "libjpeg-devel"
package "libpng-devel"
package "perl-core"
package "cronie"
package "cronie-anacron"
package "crontabs"
package "postfix"
package "sysstat"
package "iperf"

cookbook_file "/usr/local/bin/jq" do
  owner "root"
  group "root"
  mode  0755
  source "bin-jq"
end
