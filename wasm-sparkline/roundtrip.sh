#!/bin/bash

# Stop any running container first with the same name
#docker stop wasm-sparkline 2> /dev/null || true

#Remove image
#docker image rm wasm-sparkline 2> /dev/null || true


# miniserve -p 8081 ./

docker build -t wasm-sparkline .
docker run --name wasm-sparkline --rm -p 8081:8081 -v $(pwd):/app -it wasm-sparkline /bin/bash