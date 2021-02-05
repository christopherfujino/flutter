#!/usr/bin/env bash

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

if ! type protoc >/dev/null 2>&1; then
  PROTOC_LINK='https://grpc.io/docs/protoc-installation/'
  echo "Error! \"protoc\" binary required on path."
  echo "See $PROTOC_LINK for more information."
  exit 1
fi

if ! type protoc-gen-dart >/dev/null 2>&1; then
  PUB_LINK='https://pub.dev/packages/protoc_plugin'
  echo "Error! \"protoc-gen-dart\" binary required (pub package `protoc_plugin`) on path."
  echo "See $PUB_LINK for more information."
  exit 1
fi

if ! type dartfmt >/dev/null 2>&1; then
  PUB_LINK='https://pub.dev/packages/protoc_plugin'
  echo "Error! \"dartfmt\" binary required on path."
  exit 1
fi

protoc --dart_out="$DIR" --proto_path="$DIR" "$DIR/conductor_state.proto"

for SOURCE_FILE in $(ls "$DIR"/*.pb*.dart); do
  dartfmt --overwrite --line-length 120 "$SOURCE_FILE"
done
