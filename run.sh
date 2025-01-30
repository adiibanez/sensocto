#sudo sysctl -w kern.maxfiles=100000
#sudo sysctl -w kern.maxfilesperproc=100000


#ERLANG_COOKIE=testlitest AUTH_USERNAME=admin AUTH_PASSWORD=nimda_1234 mix phx.server
MIX_ENV=dev SMTP2GO_APIKEY=api-8C229504AB2F45248218104C8732F36D ERLANG_COOKIE=testlitest AUTH_USERNAME=admin AUTH_PASSWORD=nimda_1234 iex --name "node-sensocto@localhost" --cookie testlitest -S mix phx.server
#TOKEN_SIGNING_SECRET=aaa SECRET_KEY_BASE=aölsjdföalksjdflaskjdfölasjdöflkjasödlfkjasökldjfalösdjföaslkdjföasldfjöasdfkjlasöljfd ERLANG_COOKIE=testlitest AUTH_USERNAME=admin AUTH_PASSWORD=nimda_1234 MIX_ENV=prod DATABASE_URL=ecto://postgres:postgres@localhost/sensocto_dev iex --name "node@localhost" --cookie testlitest -S mix phx.server