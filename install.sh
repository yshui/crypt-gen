#!/bin/sh

DC=dmd
if [ -x `which ldc` ]; then
    DC=ldc
fi

dub build -b small --compiler=$DC
strip crypt-gen
cp -v ./crypt-gen /usr/lib/systemd/system-generators/
cp -v ./initcpio/crypt-gen /usr/lib/initcpio/install
