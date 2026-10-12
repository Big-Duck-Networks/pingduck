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
        let agent = ureq::Agent::config_builder()
            .timeout_connect(Some(Duration::from_secs(5)))
            .timeout_global(Some(Duration::from_secs(10)))
            .user_agent("pingduck-agent")
            .max_redirects(0)
            .max_redirects_will_error(false)
            // Hand back 4xx/5xx as responses so we can read their bodies.
            .http_status_as_error(false)
            .build()
            .into();
        HttpSupabaseClient { url: url.to_string(), key: key.to_string(), agent }
    }
}

fn read_body(resp: ureq::http::Response<ureq::Body>) -> String {
    let mut body = String::new();
    let _ = resp.into_body().into_reader().take(MAX_BODY).read_to_string(&mut body);
    body
}

impl SupabaseClient for HttpSupabaseClient {
    fn call(&self, function: &str, json_body: &str) -> RpcResult {
        let req = self
            .agent
            .post(&format!("{}/rest/v1/rpc/{}", self.url, function))
            .header("apikey", &self.key)
            .header("Content-Type", "application/json")
            .header("Accept", "application/json");
        match req.send(json_body) {
            Ok(resp) => RpcResult { http: resp.status().as_u16(), body: read_body(resp), network_error: false },
            Err(_) => RpcResult { network_error: true, ..RpcResult::default() },
        }
    }
}
