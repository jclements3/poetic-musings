#!/bin/bash
export PATH=$HOME/.ghcup/bin:$HOME/.cabal/bin:$HOME/tools/oss-cad-suite/bin:$PATH
cd /home/clementsj/projects/poetic-musings/Oracle/pm-top
CLASH=$HOME/.cabal/store/ghc-9.6.7/clash-ghc-1.8.5-e-clash-23ea62bbc3641e79c25b2b14b5377c7a2aa817a3d926d5bf51b28a2b52331379/bin/clash
t=0; exit_wait_only=1
while [ $(awk '/MemAvailable/{print int($2/1024)}' /proc/meminfo) -lt 1 ] && [ $t -lt 600 ]; do sleep 15; t=$((t+15)); done
echo "waited ${t}s; MemAvailable=$(awk '/MemAvailable/{print int($2/1024)}' /proc/meminfo) MB" > /dev/shm/pmtop/clash.log
$CLASH -package-db $HOME/.cabal/store/ghc-9.6.7/package.db -package-db dist-newstyle/packagedb/ghc-9.6.7 \
 -package-id clash-prelude-1.8.5-94752c298c7f4bc1b1073a5d58c57d3d90462c56a6d36c8f8f07fe05fb657b38 \
 -package clash-h2 -package irig -package pm-lib -package pm-video -package pm-net -package pm-vision -package pm-dsp -package pm-time -package theremin-clash \
 -package ghc-typelits-extra -package ghc-typelits-natnormalise -package ghc-typelits-knownnat \
 -fplugin GHC.TypeLits.Extra.Solver -fplugin GHC.TypeLits.Normalise -fplugin GHC.TypeLits.KnownNat.Solver \
 -XBangPatterns -XBinaryLiterals -XConstraintKinds -XDataKinds -XDefaultSignatures -XDeriveAnyClass -XDeriveGeneric -XDerivingStrategies -XFlexibleContexts -XKindSignatures -XMagicHash -XNoStarIsType -XNumericUnderscores -XScopedTypeVariables -XTemplateHaskell -XTypeApplications -XTypeFamilies -XTypeOperators -XNoImplicitPrelude -XRecordWildCards \
 -isrc -i../pm-time/src -i../pm-vision/src -i../pm-net/src -i../pm-dsp/src -i../pm-lib/src -i../pm-video/src -i../clash-h2/src -i../../IRIG/clash/src -outputdir /dev/shm/pmtop/obj -fclash-hdldir /dev/shm/pmtop/verilog PM.TopSnooker --verilog >> /dev/shm/pmtop/clash.log 2>&1
echo "EXIT $?" >> /dev/shm/pmtop/clash.log
