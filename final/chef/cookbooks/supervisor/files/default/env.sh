#!/bin/sh
HOME=/home/isucon
PERL_PATH="$HOME/local/perl-5.18/bin"
RUBY_PATH="$HOME/local/ruby-2.0/bin"
PYTHON_PATH="$HOME/local/python-3.3/bin"
NODE_PATH="$HOME/local/node-v0.10/bin"
GOPATH="$HOME/local/go"

PATH="$PERL_PATH:$RUBY_PATH:$PYTHON_PATH:$NODE_PATH:/usr/local/go/bin:$PATH"
umask 0022
export HOME PATH GOPATH
exec "$@"
