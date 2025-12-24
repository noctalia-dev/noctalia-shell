use icon_resolver::IconResolver;

use serde::{Deserialize, Serialize};
use std::io::{self, BufRead, Write};

#[derive(Debug, Serialize, Deserialize)]
#[serde(tag = "type")]
enum Request {
    #[serde(rename = "resolve")]
    Resolve { name: String },
    #[serde(rename = "reload")]
    Reload,
    #[serde(rename = "search")]
    Search { pattern: String },
}

#[derive(Debug, Serialize, Deserialize)]
struct ResolveResponse {
    name: String,
    path: String,
}

#[derive(Debug, Serialize, Deserialize)]
struct ReloadResponse {
    status: String,
    count: usize,
}

#[derive(Debug, Serialize, Deserialize)]
struct SearchResponse {
    matches: Vec<String>,
}

fn main() {
    let mut resolver = IconResolver::new();

    let stdin = io::stdin();
    let mut handle = stdin.lock();

    loop {
        let mut line = String::new();
        match handle.read_line(&mut line) {
            Ok(0) => break, // EOF
            Ok(_) => {
                let line = line.trim();
                if line.is_empty() {
                    continue;
                }

                match serde_json::from_str::<Request>(line) {
                    Ok(request) => {
                        let response: String = match request {
                            Request::Resolve { name } => {
                                let path = resolver.resolve(&name);
                                serde_json::to_string(&ResolveResponse { name: name.clone(), path })
                                    .unwrap_or_else(|_| r#"{"name":"","path":""}"#.to_string())
                            }
                            Request::Reload => {
                                let count = resolver.reload();
                                let reload_resp = ReloadResponse {
                                    status: "ok".to_string(),
                                    count,
                                };
                                serde_json::to_string(&reload_resp)
                                    .unwrap_or_else(|_| r#"{"status":"error","count":0}"#.to_string())
                            }
                            Request::Search { pattern } => {
                                let matches = resolver.search(&pattern);
                                let search_resp = SearchResponse { matches };
                                serde_json::to_string(&search_resp)
                                    .unwrap_or_else(|_| r#"{"matches":[]}"#.to_string())
                            }
                        };

                        println!("{}", response);
                        io::stdout().flush().unwrap_or(());
                    }
                    Err(_e) => {
                        // Return error response
                        let error_resp = ResolveResponse {
                            name: String::new(),
                            path: String::new(),
                        };
                        if let Ok(json) = serde_json::to_string(&error_resp) {
                            println!("{}", json);
                            io::stdout().flush().unwrap_or(());
                        }
                    }
                }
            }
            Err(e) => {
                eprintln!("[icon-resolver] Error reading stdin: {}", e);
                break;
            }
        }
    }
}
