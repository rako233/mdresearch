//! mdrq — the query engine behind the mdresearch Neovim plugin.
//!
//!     mdrq --protocol            print the protocol version and exit
//!     mdrq --stdin               read a request from stdin
//!     mdrq --query-file PATH     read a request from a file
//!
//! One JSON request in, JSON Lines out: one object per matching file, then a
//! trailing `{"__meta":true,...}`. See README.md.

mod filter;
mod frontmatter;
mod protocol;
mod scan;
mod value;

use anyhow::{bail, Context, Result};
use protocol::{Request, PROTOCOL};
use std::io::{Read, Write};

fn usage() -> &'static str {
    "usage: mdrq [--protocol | --stdin | --query-file PATH]"
}

fn main() {
    if let Err(e) = try_main() {
        eprintln!("mdrq: {e:#}");
        std::process::exit(1);
    }
}

fn try_main() -> Result<()> {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let mut source: Option<String> = None;

    let mut i = 0;
    while i < args.len() {
        match args[i].as_str() {
            "--protocol" => {
                println!("{PROTOCOL}");
                return Ok(());
            }
            "--version" => {
                println!("mdrq {}", env!("CARGO_PKG_VERSION"));
                return Ok(());
            }
            "-h" | "--help" => {
                println!("{}", usage());
                return Ok(());
            }
            "--stdin" => {
                let mut buf = String::new();
                std::io::stdin()
                    .read_to_string(&mut buf)
                    .context("reading the request from stdin")?;
                source = Some(buf);
            }
            "--query-file" => {
                i += 1;
                let path = args.get(i).context("--query-file needs a path")?;
                source = Some(std::fs::read_to_string(path).with_context(|| format!("reading {path}"))?);
            }
            other => bail!("unknown argument {other:?}\n{}", usage()),
        }
        i += 1;
    }

    let Some(body) = source else {
        bail!(usage());
    };
    let req: Request = serde_json::from_str(&body).context("the request is not a valid query")?;
    if req.protocol != 0 && req.protocol != PROTOCOL {
        bail!(
            "request speaks protocol {}, this mdrq speaks {PROTOCOL}",
            req.protocol
        );
    }

    let (rows, meta) = scan::run(&req)?;

    let stdout = std::io::stdout();
    let mut out = std::io::BufWriter::new(stdout.lock());
    for row in &rows {
        serde_json::to_writer(&mut out, row)?;
        out.write_all(b"\n")?;
    }
    serde_json::to_writer(&mut out, &meta)?;
    out.write_all(b"\n")?;
    out.flush()?;
    Ok(())
}
