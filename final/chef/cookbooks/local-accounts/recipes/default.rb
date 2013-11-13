#
# Cookbook Name:: local-accounts
# Recipe:: default
#
# Copyright 2013, KAYAC Inc.
#
# 
#

gem_package "ruby-shadow" do
   action :install
 end

group "isucon" do
  gid 1000
end

user "isucon" do
  uid 1000
  gid "isucon"
end

cookbook_file "/home/isucon/.bash_profile" do
  source "bash_profile"
  owner  "isucon"
  group  "isucon"
  mode    0644
end

directory "/home/isucon/local" do
  owner "isucon"
  group "isucon"
  action [:create]
end
