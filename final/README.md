## ISUCON3 Final setup howto

### setup system by chef (for CentOS-6 x86_64 only)

    # cd chef
    # ./setup-chef.sh
    # chef-solo -c solo.rb -j nodes/isucon3.json

## image/icon data

* http://30d.jp/yapcasia/6/download (C) Japan Perl Association
* http://www.smashingmagazine.com/2010/04/15/the-ultimate-free-web-designer-s-icon-set-750-icons-incl-psd-sources/

### setup initial dataset

    # su - isucon
    $ cd isucon3/final/bench
    $ ./prepare-images.sh
    $ ./init.sh

### run application

See webapp/{perl,ruby,python,node,php,go}/README.md .
