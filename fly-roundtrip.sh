# docker system prune -a
# docker buildx create --name mybuilder --driver docker-container --use
# docker buildx ls
# switch back docker buildx use default

#docker build -t sensocto .
docker buildx build -t sensocto --platform linux/amd64,linux/arm64 .

docker tag sensocto registry.fly.io/sensocto
docker push registry.fly.io/sensocto

#flyctl deploy --local-only  -i sensocto --verbose
#flyctl status
