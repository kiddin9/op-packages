# Host toolchain for the core unit tests (glibc, so ASan/UBSan work).
FROM debian:bookworm-slim
RUN apt-get update -qq \
 && apt-get install -y -qq --no-install-recommends gcc libc6-dev cmake make libjson-c-dev >/dev/null \
 && rm -rf /var/lib/apt/lists/*
