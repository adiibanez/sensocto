#!/bin/bash
#sudo sysctl -w kern.maxfiles=100000
#sudo sysctl -w kern.maxfilesperproc=100000
. .env

# BEAM VM memory and performance options:
# +hms - Sets the default heap size (in words) for processes
# +hmbs - Sets the default binary virtual heap size (in words)
# +MBas - Memory allocator settings
# +sbwt - Scheduler busy wait threshold (none/very_short/short/medium/long/very_long)
# +swt - Scheduler wakeup threshold
# +spp - Enable/disable scheduler poll for IO (true/false)

# Production-grade BEAM tuning (see docs/beam-vm-tuning.md for profiles)
# +K true       - Enable kernel poll (epoll/kqueue)
# +A 64         - Async thread pool for NIF/port operations
# +SDio 64      - Dirty IO schedulers for blocking operations
# +sbwt none    - No scheduler busy waiting (save CPU)
export ERL_FLAGS="+K true +A 64 +SDio 64 +sbwt none"

#ERLANG_COOKIE=testlitest AUTH_USERNAME=admin AUTH_PASSWORD=nimda_1234 mix phx.server
iex --erl "$ERL_FLAGS" --name $NODE_NAME --cookie testlitest -S mix phx.server
#TOKEN_SIGNING_SECRET=aaa SECRET_KEY_BASE=aölsjdföalksjdflaskjdfölasjdöflkjasödlfkjasökldjfalösdjföaslkdjföasldfjöasdfkjlasöljfd ERLANG_COOKIE=testlitest AUTH_USERNAME=admin AUTH_PASSWORD=nimda_1234 MIX_ENV=prod DATABASE_URL=ecto://postgres:postgres@localhost/sensocto_dev iex --name "node@localhost" --cookie testlitest -S mix phx.server
