### HOW TO RUN ###

    $ sudo yum install httpd24 php54 php54-mysql php54-pecl-memcached
    $ sudo ln -s /home/isucon/webapp/php/etc/isucon.php.conf.sample /etc/httpd/conf.d/isucon.php.conf
    $ sudo service httpd restart

for php54-mysql, set `LD_LIBRARY_PATH`

    LD_LIBRARY_PATH=/usr/lib64/mysql

#### SEE ALSO ####

`etc/isucon.php.conf.sample`
