# Use the official Rust image as the base image
FROM rust:1.81-slim-bullseye AS builder

# Set the working directory inside the container
WORKDIR /usr/src/wasm

# Install wasm-pack
RUN cargo install wasm-pack

# Copy the Rust project files
COPY Cargo.* ./
COPY src ./src

# Build the Wasm package
RUN wasm-pack build --target web --out-name sparkline

# --- Stage 2: Minimal Runtime Image ---
FROM debian:bullseye-slim

# Set the working directory inside the container
WORKDIR /app

# Copy the Wasm artifacts from the builder stage
COPY --from=builder /usr/src/wasm/pkg ./pkg

# Optionally, you can copy your other JavaScript, HTML etc. into this image.
# COPY index.js ./
# COPY index.html ./

# Here you can define the command to run your application (e.g. an http server) if needed.
#CMD ["http-server", "-p", "8080"]