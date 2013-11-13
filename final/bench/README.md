## HOW TO RUN Benchmark

    $ cd isucon3/final/benchmark
    $ carton install
    $ carton exec perl benchmark.pl -d /home/isucon3/image_source http://127.0.0.1/

### benchmark.pl

    benchmark.pl -d [dir] [endpoint URL]

options

* -d : path to images source dir (for upload)
* -t : sec (min 60)
* -w : workload ( 1 ... )
* -h : set HTTP Host header. requires patched Furl. See `final/misc/Furl-patched`
