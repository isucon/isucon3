#
# Cookbook Name:: supervisor
# Recipe:: default
#
# Copyright 2013, KAYAC Inc.
#
# 

package "python-setuptools"

bash "install supervisor" do
  user "root"
  cwd "/tmp"
  code "easy_install supervisor"
  not_if "which supervisord"
end

template "/etc/supervisord.conf" do
  owner "root"
  group "root"
  mode  0644
  source "supervisord.conf.erb"
end

cookbook_file "/etc/init.d/supervisord" do
  owner "root"
  group "root"
  mode  0755
  source "init-supervisord"
end

cookbook_file "/etc/sysconfig/supervisord" do
  owner "root"
  group "root"
  mode  0644
  source "sysconfig-supervisord"
end

cookbook_file "/etc/env.sh" do
  owner "root"
  group "root"
  mode  0755
  source "env.sh"
end

service "supervisord" do
  action [:enable, :start]
end
