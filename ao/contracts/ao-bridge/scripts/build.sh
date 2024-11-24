#!/bin/bash

# Recreate build directories
rm ./build/*
rm -rf ./build-lua/*

# GENERATE LUA in /build-lua
mkdir -p ./build
mkdir -p ./build-lua

# build teal
cyan build -u

cd build

# amalg.lua -s main.lua -o ../build-lua/process.lua \
#     globals dbUtils database

# FINAL RESULT is build/main.lua