# Use a specific image as the base
FROM mcr.microsoft.com/dotnet/runtime-deps:6.0-jammy as build

# Define build-time variables for versioning
ARG TARGETOS
ARG TARGETARCH
ARG RUNNER_VERSION
ARG RUNNER_CONTAINER_HOOKS_VERSION=0.6.0
ARG DOCKER_VERSION=25.0.4
ARG BUILDX_VERSION=0.13.1

# Install necessary packages
RUN apt update -y && apt install curl unzip -y

# Set the working directory
WORKDIR /actions-runner

# Download, unpack and clean up the GitHub Actions runner
RUN export RUNNER_ARCH=${TARGETARCH} \
    && if [ "$RUNNER_ARCH" = "amd64" ]; then export RUNNER_ARCH=x64 ; fi \
    && curl -f -L -o runner.tar.gz https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/actions-runner-${TARGETOS}-${RUNNER_ARCH}-${RUNNER_VERSION}.tar.gz \
    && tar xzf ./runner.tar.gz \
    && rm runner.tar.gz

# Download and extract container hooks
RUN curl -f -L -o runner-container-hooks.zip https://github.com/actions/runner-container-hooks/releases/download/v${RUNNER_CONTAINER_HOOKS_VERSION}/actions-runner-hooks-k8s-${RUNNER_CONTAINER_HOOKS_VERSION}.zip \
    && unzip ./runner-container-hooks.zip -d ./k8s \
    && rm runner-container-hooks.zip

# Download Docker and install it locally in the image
RUN export RUNNER_ARCH=${TARGETARCH} \
    && if [ "$RUNNER_ARCH" = "amd64" ]; then export DOCKER_ARCH=x86_64 ; fi \
    && if [ "$RUNNER_ARCH" = "arm64" ]; then export DOCKER_ARCH=aarch64 ; fi \
    && curl -fLo docker.tgz https://download.docker.com/${TARGETOS}/static/stable/${DOCKER_ARCH}/docker-${DOCKER_VERSION}.tgz \
    && tar zxvf docker.tgz \
    && rm -rf docker.tgz \
    && mkdir -p /usr/local/lib/docker/cli-plugins \
    && curl -fLo /usr/local/lib/docker/cli-plugins/docker-buildx \
        "https://github.com/docker/buildx/releases/download/v${BUILDX_VERSION}/buildx-v${BUILDX_VERSION}.linux-${TARGETARCH}" \
    && chmod +x /usr/local/lib/docker/cli-plugins/docker-buildx

# Final base image
FROM mcr.microsoft.com/dotnet/runtime-deps:6.0-jammy

# Environment variables and front-end setup
ENV DEBIAN_FRONTEND=noninteractive
ENV RUNNER_MANUALLY_TRAP_SIG=1
ENV ACTIONS_RUNNER_PRINT_LOG_TO_STDOUT=1
ENV ImageOS=ubuntu22

# Install essential packages
RUN apt-get update -y \
    && apt-get install -y --no-install-recommends \
    sudo \
    lsb-release \
    git \
    curl \
    build-essential \
    unzip \
    zip \
    openjdk-11-jdk \
    && rm -rf /var/lib/apt/lists/*

# Install Go
ENV GO_VERSION=1.21
RUN curl -fLo go.tar.gz https://dl.google.com/go/go${GO_VERSION}.linux-amd64.tar.gz \
    && tar -xvf go.tar.gz -C /usr/local \
    && rm go.tar.gz
ENV PATH=$PATH:/usr/local/go/bin

# Install Bazel
RUN curl -fLo bazel-installer.sh https://github.com/bazelbuild/bazel/releases/download/4.0.0/bazel-4.0.0-installer-linux-x86_64.sh \
    && chmod +x bazel-installer.sh \
    && ./bazel-installer.sh \
    && rm bazel-installer.sh

# Install GolangCI-Lint
RUN curl -sSfL https://raw.githubusercontent.com/golangci/golangci-lint/master/install.sh | sh -s v1.57.2

# Create user and groups for Docker and sudo usage
RUN adduser --disabled-password --gecos "" --uid 1001 runner \
    && groupadd docker --gid 123 \
    && usermod -aG sudo runner \
    && usermod -aG docker runner \
    && echo "%sudo   ALL=(ALL:ALL) NOPASSWD:ALL" > /etc/sudoers \
    && echo "Defaults env_keep += \"DEBIAN_FRONTEND\"" >> /etc/sudoers

# Set the work directory for the `runner` user
WORKDIR /home/runner

# Copy necessary files from the build stage
COPY --chown=runner:docker --from=build /actions-runner .
COPY --from=build /usr/local/lib/docker/cli-plugins/docker-buildx /usr/local/lib/docker/cli-plugins/docker-buildx

# Install the Docker binaries
RUN install -o root -g root -m 755 docker/* /usr/bin/ && rm -rf docker

# Switch to the runner user
USER runner