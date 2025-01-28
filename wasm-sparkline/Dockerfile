# Use the official Rust image as the base image
#FROM rust:1.81-slim-bullseye AS builder
FROM rust:bullseye

# Set the working directory inside the container
WORKDIR /app

# Install wasm-pack
RUN cargo install wasm-pack wasm-bindgen-cli
RUN cargo install --locked miniserve

# Copy the Rust project files
COPY Cargo.* ./
COPY src ./src

# Build the Wasm package
RUN wasm-pack build --target web --out-name sparkline

#RUN cp pkg/sparkline* .
# Optionally, you can copy your other JavaScript, HTML etc. into this image.
COPY index.js ./
COPY index.html ./

# Here you can define the command to run your application (e.g. an http server) if needed.
CMD ["./miniserve", "-p", "8081", "./"]
#CMD ["/bin/sh"]