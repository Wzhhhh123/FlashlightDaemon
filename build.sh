#!/bin/bash
export THEOS=~/theos
export PATH=$THEOS/bin:$PATH
cd /mnt/c/Users/Weeeiiii/led
make clean 2>/dev/null || true
make package FINALPACKAGE=1
