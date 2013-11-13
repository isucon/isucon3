#
# Cookbook Name:: isucon3
# Recipe:: default
#
# Copyright 2013, KAYAC Inc.
#

package "wget"
package "unzip"

git "/home/isucon/isucon3" do
  repository "https://github.com/kayac/isucon3.git"
  reference "master"
  action :sync
  user "isucon"
  group "isucon"
end

link "/home/isucon/webapp" do
  to "/home/isucon/isucon3/final/webapp"
  owner "isucon"
  group "isucon"
end
