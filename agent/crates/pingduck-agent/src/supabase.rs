//! Calls Supabase RPCs (PostgREST `POST /rest/v1/rpc/<fn>`) with the
//! publishable key. Behind a trait so the tests can fake the server.

use std::io::Read;
use std::time::Duration;

#[derive(Debug, Clone, Default)]
pub struct RpcResult {
    /// HTTP status; 0 when the request never completed.
    pub http: u16,
    pub body: String,
    pub network_error: bool,
}

pub trait SupabaseClient: Send + Sync {
    fn call(&self, function: &str, json_body: &str) -> RpcResult;
}

pub struct HttpSupabaseClient {
    url: String,
    key: String,
    agent: ureq::Agent,
}

const MAX_BODY: u64 = 64 * 1024;

impl HttpSupabaseClient {
    pub fn new(url: &str, key: &str) -> Self {
        let agent = ureq::AgentBuilder::new()
            .timeout_connect(Duration::from_secs(5))
            .timeout(Duration::from_secs(10))
            .user_agent("pingduck-agent")
            .redirects(0)
            .build();
        HttpSupabaseClient { url: url.to_string(), key: key.to_string(), agent }
    }
}

fn read_body(resp: ureq::Response) -> String {
    let mut body = String::new();
    let _ = resp.into_reader().take(MAX_BODY).read_to_string(&mut body);
    body
}

impl SupabaseClient for HttpSupabaseClient {
    fn call(&self, function: &str, json_body: &str) -> RpcResult {
        let req = self
            .agent
            .post(&format!("{}/rest/v1/rpc/{}", self.url, function))
            .set("apikey", &self.key)
            .set("Content-Type", "application/json")
            .set("Accept", "application/json");
        match req.send_string(json_body) {
            Ok(resp) => RpcResult { http: resp.status(), body: read_body(resp), network_error: false },
            Err(ureq::Error::Status(code, resp)) => RpcResult { http: code, body: read_body(resp), network_error: false },
            Err(ureq::Error::Transport(_)) => RpcResult { network_error: true, ..RpcResult::default() },
        }
    }
}
