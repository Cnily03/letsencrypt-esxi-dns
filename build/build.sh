#!/bin/bash
#
# Copyright (c) Johannes Feichtner <johannes@web-wack.at>
#
# Script to build letsencrypt-esxi-dns VIB using VIB Author

LOCALDIR=$(dirname "$(readlink -f "$0")")
cd "${LOCALDIR}/.." || exit

docker rmi -f letsencrypt-esxi-dns 2> /dev/null
rm -rf artifacts
docker build -t letsencrypt-esxi-dns -f build/Dockerfile .
docker run -i -v "${PWD}"/artifacts:/artifacts letsencrypt-esxi-dns sh << COMMANDS
cp letsencrypt-esxi-dns/build/letsencrypt-esxi-dns* /artifacts
COMMANDS
