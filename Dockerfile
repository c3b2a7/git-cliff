# syntax=docker/dockerfile:1.4.3-labs
FROM lukemathwalker/cargo-chef:0.1.71-rust-1.85.0-slim-bookworm@sha256:048654cf424dcc1efd4f6ad2e627c7526cb909cbf9172d988cd6f8491a7a2828 AS chef
WORKDIR app

FROM chef AS planner
COPY . .
RUN cargo chef prepare --recipe-path recipe.json

FROM chef AS builder
COPY --from=planner /app/recipe.json recipe.json
ENV CARGO_NET_GIT_FETCH_WITH_CLI=true
RUN cargo chef cook --release --recipe-path recipe.json
COPY . .
RUN cargo build --release --locked --no-default-features --features github --features gitlab --features bitbucket
RUN rm -f target/release/deps/git_cliff*

FROM debian:bookworm-slim@sha256:e5865e6858dacc255bead044a7f2d0ad8c362433cfaa5acefb670c1edf54dfef as runner

# Everything inside this container will be explicitly mounted by the end user,
# so we can sidestep some Git security restrictions. This app recommends
# mounting data to /app, but this *can* be changed externally and *will* be
# changed when run by GitHub Actions, so we need to cover our bases.
RUN echo '[safe]\n\tdirectory = *' > /etc/gitconfig

COPY --from=builder /app/target/release/git-cliff /usr/local/bin
WORKDIR app

# Even if the repository is marked as safe, GitHub Actions and some other
# environments insist on running the entrypoint as root inside the container
# even when being run by a non privileged user on their own files. Here we
# check the ownership of the workdir (which may or may not be /app) and change
# our effective user/group ID to match.
RUN cat <<'EOF' > /usr/local/bin/entrypoint.sh
#!/bin/sh
if [ "$(id -u)" -ne "$(stat -c '%u' .)" ]; then
  eids="$(stat -c '--euid %u --egid %g' .)"
fi
exec ${eids:+setpriv --clear-groups $eids} git-cliff $@
EOF
ENTRYPOINT ["sh", "/usr/local/bin/entrypoint.sh"]
