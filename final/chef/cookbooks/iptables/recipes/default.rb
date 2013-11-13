#
# Cookbook Name:: iptables
# Recipe:: default
#
# Copyright 2013, KAYAC Inc.
#
# 
#

cookbook_file "/etc/sysconfig/iptables" do
  owner "root"
  group "root"
  mode  0644
  source "sysconfig-iptables"
end

service "iptables" do
  action [:enable, :start]
end
