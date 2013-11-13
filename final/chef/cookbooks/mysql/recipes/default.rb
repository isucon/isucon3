#
# Cookbook Name:: mysql
# Recipe:: default
#
# Copyright 2013, KAYAC Inc.
#
# 
#

package "mysql-community-release" do
  action :remove
end

package "mysql"
package "compat-mysql51"
package "mysql-server"
package "mysql-libs"
package "mysql-devel"

template "/etc/my.cnf" do
  owner "root"
  mode  0644
  source "my.cnf.erb"
end

service "mysqld" do
  action [:enable, :start]
end
