#
# Cookbook Name:: golang
# Recipe:: default
#
# Copyright 2013, KAYAC Inc.
#
# 
#

remote_file "/tmp/go1.1.2.linux-amd64.tar.gz" do
  source "https://go.googlecode.com/files/go1.1.2.linux-amd64.tar.gz"
  not_if { ::File.exists? "/usr/local/go/bin/go" }
end

bash "install go" do
  user "root"
  cwd "/usr/local"
  code "tar zxvf /tmp/go1.1.2.linux-amd64.tar.gz"
  not_if { ::File.exists? "/usr/local/go/bin/go" }
end
