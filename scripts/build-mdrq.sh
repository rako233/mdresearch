#!/usr/bin/env sh
# Build the optional Rust backend and report where the plugin will find it.
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
crate="$root/rust/mdrq"

if ! command -v cargo >/dev/null 2>&1; then
  echo "cargo not found — install Rust from https://rustup.rs, or keep using the Lua backend" >&2
  exit 1
fi

cargo build --release --manifest-path "$crate/Cargo.toml"

bin="$crate/target/release/mdrq"
printf '\nbuilt %s (protocol %s)\n' "$bin" "$("$bin" --protocol)"
printf 'mdresearch picks it up automatically; :checkhealth mdresearch to confirm.\n'
