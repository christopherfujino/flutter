FROM "debian:10.4"

RUN apt-get update -qq && \
  apt-get upgrade -y && \
  apt-get install -y \
    git \
    curl \
    android-sdk \
    default-jdk-headless \
    unzip && \
  apt-get clean

# TODO delete
RUN apt-get install -y \
    vim &&\
  apt-get clean

COPY . /flutter

RUN mkdir /flutter/bin/cache

WORKDIR /flutter

# Download arm64 build of dart sdk
RUN curl -o bin/cache/dart-sdk.zip https://storage.googleapis.com/dart-archive/channels/stable/release/2.8.4/sdk/dartsdk-linux-arm64-release.zip

# Insert into cache
RUN unzip bin/cache/dart-sdk.zip -d bin/cache

# Override update_dart_sdk.sh script
RUN cp bin/internal/engine.version bin/cache/engine-dart-sdk.stamp

# Compile tool
RUN bin/flutter precache

RUN bin/flutter doctor -v
