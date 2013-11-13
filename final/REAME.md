## ISUCON3 Final setup howto

### setup system by chef (for CentOS-6 x86_64)

    # cd chef
    # chef-solo -c solo.rb -j nodes/isucon3.json

## image/icon data

* (C) Japan Perl Association http://30d.jp/yapcasia/6/download
* http://www.smashingmagazine.com/2010/04/15/the-ultimate-free-web-designer-s-icon-set-750-icons-incl-psd-sources/

### setup initial dataset

    $ cd isucon3/final/bench
    $ ./prepare-images.sh
    $ ./init.sh

### run application

See webapp/{perl,ruby,python,node,php,go}/README.md .
