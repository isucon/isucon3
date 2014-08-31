file_cache_path '/tmp/chef-solo'
cookbook_path   Dir.pwd + '/cookbooks'
role_path       Dir.pwd + '/roles'
node_name       `hostname -s`.chomp
ssl_verify_mode :verify_peer
