docker build -t sensocto .

docker tag sensocto registry.fly.io/sensocto
docker push registry.fly.io/sensocto

#flyctl deploy --verbose --app sensocto

#flyctl status
