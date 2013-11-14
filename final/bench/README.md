## HOW TO RUN Benchmark

    $ cd isucon3/final/benchmark
    $ carton install
    $ carton exec perl bench.pl -d /home/isucon/image_source http://127.0.0.1/

### bench.pl

    bench.pl -d [dir] [endpoint URL]

options

* -d : path to images source dir (for upload)
* -t : sec (min 60)
* -w : workload ( 1 ... )
* -h : set HTTP Host header. requires patched Furl. See `final/misc/Furl-patched`
