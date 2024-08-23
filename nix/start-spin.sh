#!/bin/sh


# enter terminal mux
##abduco -c session1 dvtm
##cloudflared tunnel --config $HOME/.cloudflared/config.yml run $CF_TUNNEL_ID 

# env var to workaround mem allocation error
export SPIN_WASMTIME_TOTAL_MEMORIES=50

# another switch to reduce mem footprint
##spin up --disable-pooling

spin up

