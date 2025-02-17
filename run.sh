#sudo sysctl -w kern.maxfiles=100000
#sudo sysctl -w kern.maxfilesperproc=100000
source .env
#ERLANG_COOKIE=testlitest AUTH_USERNAME=admin AUTH_PASSWORD=nimda_1234 mix phx.server
iex --name "sensocto@localhost" --cookie testlitest -S mix phx.server
#TOKEN_SIGNING_SECRET=aaa SECRET_KEY_BASE=aölsjdföalksjdflaskjdfölasjdöflkjasödlfkjasökldjfalösdjföaslkdjföasldfjöasdfkjlasöljfd ERLANG_COOKIE=testlitest AUTH_USERNAME=admin AUTH_PASSWORD=nimda_1234 MIX_ENV=prod DATABASE_URL=ecto://postgres:postgres@localhost/sensocto_dev iex --name "node@localhost" --cookie testlitest -S mix phx.server
