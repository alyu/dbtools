#!/usr/bin/env bash

[ $# -lt 1 ] && echo "$(basename $0) <remote host> [port|8888]" && exit 1

[ ! $(command -v nc) ] && echo "Unable to find nc. Please install it first." && exit 1
[ ! $(command -v gzip) ] && echo "Unable to find gzip. Please install it first." && exit 1
[ ! $(command -v pigz) ] && echo "Unable to find pigz. Please install it first." && exit 1
[ ! $(command -v pv) ]  && echo "Unable to find pv. Please install it first." && exit 1

port=8888
[ $# -gt 1 ] && port=$2
host=$1

echo "Receiving from $host:$port..."
time nc $host $port | pigz -d | pv -tab | tar xf -
echo "Done!"