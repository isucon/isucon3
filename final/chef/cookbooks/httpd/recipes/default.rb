#
# Cookbook Name:: httpd
# Recipe:: default
#
# Copyright 2013, KAYAC Inc.
#
# 
#
#

package "httpd"
package "httpd-devel"

cookbook_file "/etc/httpd/conf.d/isucon.conf" do
  source "isucon.conf"
  owner "root"
  group "root"
  mode  0644
end

service "httpd" do
 if node[:hostname] =~ /1$/
   action [:enable, :start]
 else
   action [:disable, :stop]
 end
end
