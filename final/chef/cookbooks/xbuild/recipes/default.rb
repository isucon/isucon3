#
# Cookbook Name:: xbuild
# Recipe:: default
#
# Copyright 2013, KAYAC Inc.
#

xbuild_dir = (node[:xbuild][:user] == "root") ? "/usr/local/xbuild" : "/home/#{node[:xbuild][:user]}/xbuild"
home = (node[:xbuild][:user] == "root") ? "/root" : "/home/#{node[:xbuild][:user]}"

git xbuild_dir do
  repository "https://github.com/tagomoris/xbuild.git"
  reference "master"
  action :sync
  user node[:xbuild][:user]
end

%w{ perl ruby node python php }.each do |lang|
  next unless node[:xbuild][lang]
  bash "install #{lang}" do
    user node[:xbuild][:user]
    cwd xbuild_dir
    code "HOME=#{home} ./install #{lang} #{node[:xbuild][lang][:version]} #{node[:xbuild][lang][:prefix]}"
    not_if { File.exists? node[:xbuild][lang][:prefix] }
  end
end
