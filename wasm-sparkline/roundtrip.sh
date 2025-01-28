#!/bin/bash

# Stop any running container first with the same name
docker stop wasm-sparkline 2> /dev/null || true

#Remove image
docker image rm wasm-sparkline 2> /dev/null || true


docker build -t wasm-sparkline .
docker run -p 8080:8080 -v $(pwd):/host -t wasm-sparkline