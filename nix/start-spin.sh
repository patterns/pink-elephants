#!/bin/sh


# env var to workaround mem allocation error
export SPIN_WASMTIME_TOTAL_MEMORIES=50

# another switch to reduce mem footprint
##spin up --disable-pooling

spin up

