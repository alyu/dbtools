#!/usr/bin/env bash

[ $# -lt 1 ] && echo "$(basename $0) <source dir> [compression level|5] [port|8888]" && exit 1

[ ! $(command -v nc) ] && echo "Unable to find nc. Please install it first." && exit 1
[ ! $(command -v gzip) ] && echo "Unable to find gzip. Please install it first." && exit 1
[ ! $(command -v pigz) ] && echo "Unable to find pigz. Please install it first." && exit 1
[ ! $(command -v pv) ]  && echo "Unable to find pv. Please install it first." && exit 1

[[ ! -d "$1" && ! -L $1 ]] && echo "$1 is not a directory!" && exit

port=8888
c=5
[ $# -gt 1 ] && c=$2
[ $# -gt 2 ] && c=$2 && port=$3
dir=$1

size=$(du -sh $dir | cut -f1)
echo "Sending content of $dir ($size) on port $port with compression level $c..."
[[ $OSTYPE =~ ^darwin ]] && tar -c $1 | pv -tab | pigz -$c | nc -l $port
[[ ! $OSTYPE =~ ^darwin ]] && tar -c $1 | pv -tabes $(du -sb $dir | cut -f1) | pigz -$c | nc -l $port
echo "Done!"
