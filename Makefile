.PHONY: test test-lua test-rust build fmt clean

test: test-lua test-rust

test-lua:
	nvim --headless -l tests/run.lua

test-rust:
	cargo test --manifest-path rust/mdrq/Cargo.toml

build:
	./scripts/build-mdrq.sh

fmt:
	cargo fmt --manifest-path rust/mdrq/Cargo.toml
	@command -v stylua >/dev/null 2>&1 && stylua lua tests || echo "stylua not installed, skipping Lua formatting"

clean:
	cargo clean --manifest-path rust/mdrq/Cargo.toml
