#sudo sysctl -w kern.maxfiles=100000
#sudo sysctl -w kern.maxfilesperproc=100000
source .env

# BEAM VM memory and performance options:
# +hms - Sets the default heap size (in words) for processes
# +hmbs - Sets the default binary virtual heap size (in words)
# +MBas - Memory allocator settings
# +sbwt - Scheduler busy wait threshold (none/very_short/short/medium/long/very_long)
# +swt - Scheduler wakeup threshold
# +spp - Enable/disable scheduler poll for IO (true/false)

# Uncomment/adjust these based on your needs:
# ERL_FLAGS="+hms 8388608"  # 8MB default heap per process (default is ~233 words)
export ERL_FLAGS=""

#ERLANG_COOKIE=testlitest AUTH_USERNAME=admin AUTH_PASSWORD=nimda_1234 mix phx.server
iex --erl "$ERL_FLAGS" --name $NODE_NAME --cookie testlitest -S mix phx.server
#TOKEN_SIGNING_SECRET=aaa SECRET_KEY_BASE=aölsjdföalksjdflaskjdfölasjdöflkjasödlfkjasökldjfalösdjföaslkdjföasldfjöasdfkjlasöljfd ERLANG_COOKIE=testlitest AUTH_USERNAME=admin AUTH_PASSWORD=nimda_1234 MIX_ENV=prod DATABASE_URL=ecto://postgres:postgres@localhost/sensocto_dev iex --name "node@localhost" --cookie testlitest -S mix phx.server
