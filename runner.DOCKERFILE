# Use specific images as stages for preparation
FROM golang:1.21-alpine3.19 AS go-builder
FROM golangci/golangci-lint:v1.57.2-alpine AS golangci-lint-base

# Final base image
FROM ghcr.io/actions/actions-runner:latest

USER root

# Install essential packages
RUN apt-get update -y \
    && apt-get install -y --no-install-recommends \
    sudo \
    lsb-release \
    git \
    curl \
    wget \
    unzip \
    zip \
    g++ \
    openjdk-11-jdk \
    && rm -rf /var/lib/apt/lists/*

# Copy Go from the Go builder stage
COPY --from=go-builder /usr/local/go/ /usr/local/go/

# Set the environment variable for Go
ENV PATH="/usr/local/go/bin:${PATH}"

# # Install Bazelisk
# RUN curl -LJO "https://github.com/bazelbuild/bazelisk/releases/latest/download/bazelisk-linux-amd64" \
#     && mv bazelisk-linux-amd64 /usr/local/bin/bazel \
#     && chmod +x /usr/local/bin/bazel

COPY --from=gcr.io/bazel-public/bazel:latest /usr/local/bin/bazel /usr/bin/bazel

# Copy GolangCI-Lint binary from its official image
COPY --from=golangci-lint-base /usr/bin/golangci-lint /usr/bin/golangci-lint

USER runner
