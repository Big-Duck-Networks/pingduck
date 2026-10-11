//! The agent's behaviour, free of sockets so it can be unit-tested: the LAN
//! HTTP routes, pairing, and the heartbeat that notices a revoke.

use std::collections::{HashMap, VecDeque};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex};

use serde_json::{json, Value};

use crate::config::Config;
use crate::http::{HttpReply, HttpRequest};
use crate::state::StateStore;
use crate::supabase::SupabaseClient;

/// UPnP device type the app looks for; the core reports it as "upnp:PingDuckAgent".
pub const DEVICE_TYPE: &str = "urn:pingduck-app:device:PingDuckAgent:1";
pub const MANUFACTURER: &str = "PingDuck";
pub const MODEL_NAME: &str = "PingDuck Agent";

/// The alphabet create_pairing_code draws from (no 0/O, 1/I/L).
const CODE_ALPHABET: &str = "ABCDEFGHJKMNPQRSTUVWXYZ23456789";
const PAIR_ATTEMPTS_PER_MINUTE: usize = 5;

/// Uppercased code if it can be one create_pairing_code makes (8 characters
/// from its alphabet; spaces and dashes ignored), otherwise None.
pub fn normalize_code(raw: &str) -> Option<String> {
    let code: String = raw.chars().filter(|c| !matches!(c, ' ' | '\t' | '-')).map(|c| c.to_ascii_uppercase()).collect();
    (code.len() == 8 && code.chars().all(|c| CODE_ALPHABET.contains(c))).then_some(code)
}

pub fn xml_escape(s: &str) -> String {
    let mut out = String::with_capacity(s.len());
    for c in s.chars() {
        match c {
            '&' => out.push_str("&amp;"),
            '<' => out.push_str("&lt;"),
            '>' => out.push_str("&gt;"),
            '"' => out.push_str("&quot;"),
            '\'' => out.push_str("&apos;"),
            c if (c as u32) < 0x20 => {}
            c => out.push(c),
        }
    }
    out
}

#[derive(Debug, PartialEq, Eq, Clone, Copy)]
pub enum Heartbeat {
    Active,
    Revoked,
    Unpaired,
    Error,
}

fn error(status: u16, code: &str) -> HttpReply {
    HttpReply::json(status, json!({ "error": code }).to_string())
}

fn str_field<'a>(v: &'a Value, key: &str) -> &'a str {
    v.get(key).and_then(Value::as_str).unwrap_or("")
}

/// Milliseconds on a monotonic clock.
pub type Clock = Box<dyn Fn() -> i64 + Send + Sync>;

pub struct Agent {
    config: Config,
    store: Arc<StateStore>,
    supabase: Arc<dyn SupabaseClient>,
    version: String,
    clock: Clock,
    pairing: AtomicBool,
    /// Pair POSTs per peer in the last minute.
    attempts: Mutex<HashMap<String, VecDeque<i64>>>,
}

impl Agent {
    pub fn new(config: Config, store: Arc<StateStore>, supabase: Arc<dyn SupabaseClient>, version: String, clock: Clock) -> Self {
        Agent { config, store, supabase, version, clock, pairing: AtomicBool::new(false), attempts: Mutex::default() }
    }

    pub fn config(&self) -> &Config {
        &self.config
    }

    pub fn description_xml(&self) -> String {
        let s = self.store.get();
        // No modelNumber: the core appends it to modelName, and the app
        // matches the model exactly.
        format!(
            "<?xml version=\"1.0\"?>\n<root xmlns=\"urn:schemas-upnp-org:device-1-0\">\n\
             <specVersion><major>1</major><minor>0</minor></specVersion>\n<device>\n\
             <deviceType>{DEVICE_TYPE}</deviceType>\n\
             <friendlyName>{}</friendlyName>\n\
             <manufacturer>{MANUFACTURER}</manufacturer>\n\
             <manufacturerURL>https://pingduck.app</manufacturerURL>\n\
             <modelName>{MODEL_NAME}</modelName>\n\
             <UDN>uuid:{}</UDN>\n\
             <presentationURL>/pingduck/v1/info</presentationURL>\n\
             </device>\n</root>\n",
            xml_escape(&self.config.name),
            s.instance_id
        )
    }

    pub fn info_json(&self) -> String {
        let s = self.store.get();
        json!({
            "app": "pingduck-agent",
            "api": 1,
            "instance_id": s.instance_id,
            "name": self.config.name,
            "version": self.version,
            "paired": s.paired(),
            "agent_id": if s.paired() { Value::from(s.agent_id) } else { Value::Null },
        })
        .to_string()
    }

    /// Every LAN request lands here.
    pub fn handle(&self, req: &HttpRequest, peer: &str) -> HttpReply {
        let route = |method: &str, ok: &dyn Fn() -> HttpReply| {
            if req.method == method { ok() } else { error(405, "method_not_allowed") }
        };
        match req.path.as_str() {
            "/description.xml" => route("GET", &|| HttpReply {
                status: 200,
                body: self.description_xml(),
                content_type: "text/xml; charset=\"utf-8\"",
            }),
            "/pingduck/v1/info" => route("GET", &|| HttpReply::json(200, self.info_json())),
            "/pingduck/v1/pair" => route("POST", &|| self.pair(req, peer)),
            _ => error(404, "not_found"),
        }
    }

    fn allow(&self, peer: &str) -> bool {
        let now = (self.clock)();
        let mut attempts = self.attempts.lock().unwrap();
        if attempts.len() > 256 {
            attempts.clear(); // bound memory under a spray of source IPs
        }
        let q = attempts.entry(peer.to_string()).or_default();
        while q.front().is_some_and(|&t| now - t >= 60_000) {
            q.pop_front();
        }
        if q.len() >= PAIR_ATTEMPTS_PER_MINUTE {
            return false;
        }
        q.push_back(now);
        true
    }

    fn pair(&self, req: &HttpRequest, peer: &str) -> HttpReply {
        // A JSON content type means a web page on the LAN can't send this
        // without a CORS preflight, which this server never answers.
        if !req.headers.get("content-type").is_some_and(|ct| ct.starts_with("application/json")) {
            return error(415, "json_required");
        }
        if !self.allow(peer) {
            return error(429, "too_many_attempts");
        }
        if self.store.get().paired() {
            return error(409, "already_paired");
        }
        let Ok(body) = serde_json::from_str::<Value>(&req.body) else { return error(400, "bad_code") };
        crate::log!("pair: request from {peer}");
        self.claim(str_field(&body, "code"))
    }

    /// Redeems a pairing code with Supabase. Used by POST /pair and by the
    /// PINGDUCK_PAIRING_CODE fallback.
    pub fn claim(&self, raw_code: &str) -> HttpReply {
        let Some(code) = normalize_code(raw_code) else { return error(400, "bad_code") };
        if self.pairing.compare_exchange(false, true, Ordering::SeqCst, Ordering::SeqCst).is_err() {
            return error(429, "busy");
        }
        struct Release<'a>(&'a AtomicBool);
        impl Drop for Release<'_> {
            fn drop(&mut self) {
                self.0.store(false, Ordering::SeqCst);
            }
        }
        let _release = Release(&self.pairing);

        if self.store.get().paired() {
            return error(409, "already_paired");
        }
        let args = json!({ "p_code": code, "p_name": self.config.name, "p_version": self.version });
        let r = self.supabase.call("claim_pairing_code", &args.to_string());
        if r.network_error || r.http == 0 || r.http >= 500 {
            crate::log!("pair: could not reach Supabase (http {})", r.http);
            return error(502, "upstream");
        }
        let j: Value = serde_json::from_str(&r.body).unwrap_or(Value::Null);
        if r.http != 200 {
            if str_field(&j, "message").contains("invalid or expired") {
                crate::log!("pair: code rejected (invalid or expired)");
                return error(400, "invalid_code");
            }
            crate::log!("pair: Supabase refused (http {})", r.http);
            return error(502, "upstream");
        }

        let mut s = self.store.get();
        s.agent_id = str_field(&j, "agent_id").into();
        s.network_id = str_field(&j, "network_id").into();
        s.token = str_field(&j, "token").into();
        if s.agent_id.is_empty() || s.token.len() != 64 {
            crate::log!("pair: unexpected answer from Supabase");
            return error(502, "upstream");
        }
        let (agent_id, network_id) = (s.agent_id.clone(), s.network_id.clone());
        if !self.store.set(s) {
            crate::log!("pair: paired, but the state file could not be written");
        }
        crate::log!("pair: paired as agent {agent_id}");
        HttpReply::json(200, json!({ "agent_id": agent_id, "network_id": network_id }).to_string())
    }

    /// Checks in with Supabase; on "revoked" clears the token so the agent
    /// can be added again.
    pub fn heartbeat(&self) -> Heartbeat {
        let s = self.store.get();
        if !s.paired() {
            return Heartbeat::Unpaired;
        }
        let r = self.supabase.call("agent_heartbeat", &json!({ "p_token": s.token }).to_string());
        if r.network_error || r.http != 200 {
            return Heartbeat::Error;
        }
        let j: Value = serde_json::from_str(&r.body).unwrap_or(Value::Null);
        match str_field(&j, "status") {
            "active" => Heartbeat::Active,
            "revoked" => {
                // Only forget the token we sent; a pair that finished meanwhile wins.
                if self.store.get().token == s.token {
                    self.store.clear_pairing();
                    crate::log!("heartbeat: revoked from the app; waiting to be added again");
                }
                Heartbeat::Revoked
            }
            _ => Heartbeat::Error,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::supabase::RpcResult;
    use std::sync::atomic::AtomicI64;

    fn token() -> String {
        "a".repeat(64)
    }

    struct FakeSupabase {
        calls: Mutex<Vec<(String, String)>>,
        next: Mutex<RpcResult>,
    }

    impl FakeSupabase {
        fn new() -> Arc<Self> {
            let fake = Arc::new(FakeSupabase { calls: Mutex::default(), next: Mutex::default() });
            fake.answer(200, &json!({"agent_id": "agent-1", "network_id": "net-1", "token": token()}).to_string());
            fake
        }
        fn answer(&self, http: u16, body: &str) {
            *self.next.lock().unwrap() = RpcResult { http, body: body.into(), network_error: false };
        }
        fn down(&self) {
            *self.next.lock().unwrap() = RpcResult { network_error: true, ..RpcResult::default() };
        }
        fn calls(&self) -> Vec<(String, String)> {
            self.calls.lock().unwrap().clone()
        }
    }

    impl SupabaseClient for FakeSupabase {
        fn call(&self, function: &str, body: &str) -> RpcResult {
            self.calls.lock().unwrap().push((function.into(), body.into()));
            self.next.lock().unwrap().clone()
        }
    }

    struct Fixture {
        _dir: tempfile::TempDir,
        store: Arc<StateStore>,
        supabase: Arc<FakeSupabase>,
        now: Arc<AtomicI64>,
        agent: Agent,
    }

    fn fixture() -> Fixture {
        let dir = tempfile::tempdir().unwrap();
        let store = Arc::new(StateStore::open(dir.path()));
        let supabase = FakeSupabase::new();
        let now = Arc::new(AtomicI64::new(1_000_000));
        let mut config = Config::load(|_| None);
        config.name = "homelab <lab>".into();
        let clock_now = now.clone();
        let agent = Agent::new(config, store.clone(), supabase.clone(), "0.9.0".into(), Box::new(move || clock_now.load(Ordering::Relaxed)));
        Fixture { _dir: dir, store, supabase, now, agent }
    }

    fn post_pair(f: &Fixture, body: &str, ip: &str) -> HttpReply {
        let mut r = HttpRequest { method: "POST".into(), path: "/pingduck/v1/pair".into(), body: body.into(), ..Default::default() };
        r.headers.insert("content-type".into(), "application/json".into());
        f.agent.handle(&r, ip)
    }

    fn json_of(r: &HttpReply) -> Value {
        serde_json::from_str(&r.body).unwrap()
    }

    const IP: &str = "10.42.0.17";

    #[test]
    fn a_good_code_is_redeemed_and_the_token_stays_private() {
        let f = fixture();
        let r = post_pair(&f, r#"{"code":"abcd 2345"}"#, IP);
        assert_eq!(r.status, 200);
        assert_eq!(json_of(&r)["agent_id"], "agent-1");
        assert!(!r.body.contains(&token()));
        let calls = f.supabase.calls();
        assert_eq!(calls.len(), 1);
        assert_eq!(calls[0].0, "claim_pairing_code");
        let args: Value = serde_json::from_str(&calls[0].1).unwrap();
        assert_eq!(args["p_code"], "ABCD2345");
        assert_eq!(args["p_name"], "homelab <lab>");
        assert!(f.store.get().paired());
        assert!(!f.agent.info_json().contains(&token()));
        assert_eq!(serde_json::from_str::<Value>(&f.agent.info_json()).unwrap()["paired"], true);
    }

    #[test]
    fn a_paired_agent_refuses_to_pair_again() {
        let f = fixture();
        post_pair(&f, r#"{"code":"ABCD2345"}"#, IP);
        assert_eq!(post_pair(&f, r#"{"code":"WXYZ2345"}"#, "10.42.0.99").status, 409);
        assert_eq!(f.supabase.calls().len(), 1);
        assert_eq!(f.store.get().agent_id, "agent-1");
    }

    #[test]
    fn malformed_codes_never_reach_supabase() {
        let f = fixture();
        for (i, body) in [r#"{"code":"ABC"}"#, r#"{"code":"ABCD234O"}"#, r#"{"code":12345678}"#, "not json", "{}"].iter().enumerate() {
            assert_eq!(post_pair(&f, body, &format!("10.0.0.{i}")).status, 400, "{body}");
        }
        assert!(f.supabase.calls().is_empty());
    }

    #[test]
    fn an_expired_code_is_reported_not_an_outage() {
        let f = fixture();
        f.supabase.answer(403, r#"{"code":"28000","message":"invalid or expired pairing code"}"#);
        let r = post_pair(&f, r#"{"code":"ABCD2345"}"#, IP);
        assert_eq!(r.status, 400);
        assert_eq!(json_of(&r)["error"], "invalid_code");
        assert!(!f.store.get().paired());
    }

    #[test]
    fn supabase_down_is_a_502_and_changes_nothing() {
        let f = fixture();
        f.supabase.down();
        assert_eq!(post_pair(&f, r#"{"code":"ABCD2345"}"#, IP).status, 502);
        f.supabase.answer(200, r#"{"agent_id":"x"}"#);
        assert_eq!(post_pair(&f, r#"{"code":"ABCD2345"}"#, IP).status, 502);
        assert!(!f.store.get().paired());
    }

    #[test]
    fn needs_a_json_content_type() {
        let f = fixture();
        let mut r = HttpRequest { method: "POST".into(), path: "/pingduck/v1/pair".into(), body: r#"{"code":"ABCD2345"}"#.into(), ..Default::default() };
        r.headers.insert("content-type".into(), "text/plain".into());
        assert_eq!(f.agent.handle(&r, IP).status, 415);
        assert!(f.supabase.calls().is_empty());
    }

    #[test]
    fn at_most_5_attempts_a_minute_from_one_address() {
        let f = fixture();
        f.supabase.answer(403, r#"{"message":"invalid or expired pairing code"}"#);
        for _ in 0..5 {
            assert_eq!(post_pair(&f, r#"{"code":"ABCD2345"}"#, IP).status, 400);
        }
        assert_eq!(post_pair(&f, r#"{"code":"ABCD2345"}"#, IP).status, 429);
        assert_eq!(post_pair(&f, r#"{"code":"ABCD2345"}"#, "10.42.0.18").status, 400);
        f.now.fetch_add(60_000, Ordering::Relaxed);
        assert_eq!(post_pair(&f, r#"{"code":"ABCD2345"}"#, IP).status, 400);
    }

    #[test]
    fn the_env_var_fallback_uses_the_same_claim() {
        let f = fixture();
        assert_eq!(f.agent.claim("abcd-2345").status, 200);
        assert!(f.store.get().paired());
    }

    #[test]
    fn heartbeat_does_nothing_while_unpaired() {
        let f = fixture();
        assert_eq!(f.agent.heartbeat(), Heartbeat::Unpaired);
        assert!(f.supabase.calls().is_empty());
    }

    #[test]
    fn revoked_clears_the_pairing_but_keeps_the_instance_id() {
        let f = fixture();
        post_pair(&f, r#"{"code":"ABCD2345"}"#, IP);
        let instance = f.store.get().instance_id;
        f.supabase.answer(200, r#"{"status":"active"}"#);
        assert_eq!(f.agent.heartbeat(), Heartbeat::Active);
        assert!(f.store.get().paired());
        f.supabase.answer(200, r#"{"status":"revoked"}"#);
        assert_eq!(f.agent.heartbeat(), Heartbeat::Revoked);
        assert!(!f.store.get().paired());
        assert_eq!(f.store.get().instance_id, instance);
        f.supabase.answer(200, &json!({"agent_id": "agent-2", "network_id": "net-1", "token": token()}).to_string());
        assert_eq!(post_pair(&f, r#"{"code":"ABCD2345"}"#, IP).status, 200); // can be added again
    }

    #[test]
    fn an_outage_keeps_the_pairing() {
        let f = fixture();
        post_pair(&f, r#"{"code":"ABCD2345"}"#, IP);
        f.supabase.down();
        assert_eq!(f.agent.heartbeat(), Heartbeat::Error);
        f.supabase.answer(503, "");
        assert_eq!(f.agent.heartbeat(), Heartbeat::Error);
        assert!(f.store.get().paired());
    }

    #[test]
    fn routes_and_methods() {
        let f = fixture();
        let get = |path: &str, method: &str| {
            f.agent.handle(&HttpRequest { method: method.into(), path: path.into(), ..Default::default() }, IP)
        };
        let info = json_of(&get("/pingduck/v1/info", "GET"));
        assert_eq!(info["app"], "pingduck-agent");
        assert_eq!(info["api"], 1);
        assert_eq!(info["paired"], false);
        assert!(info["agent_id"].is_null());
        assert_eq!(get("/pingduck/v1/info", "POST").status, 405);
        assert_eq!(get("/pingduck/v1/pair", "GET").status, 405);
        assert_eq!(get("/etc/passwd", "GET").status, 404);
    }

    #[test]
    fn the_core_reads_the_description_as_a_pingduck_agent() {
        let f = fixture();
        let d = pingduck_core_sys::describe(&f.agent.description_xml());
        assert_eq!(d.vendor, "PingDuck");
        assert_eq!(d.model, "PingDuck Agent");
        assert_eq!(d.hostname, "homelab <lab>"); // escaped in XML, intact after parsing
        assert!(d.services.contains("upnp:PingDuckAgent"), "{}", d.services);
    }

    #[test]
    fn codes_normalize() {
        assert_eq!(normalize_code(" abcd-2345 ").as_deref(), Some("ABCD2345"));
        assert_eq!(normalize_code("ABCD2345X"), None);
        assert_eq!(normalize_code("ABCD2I45"), None);
    }
}
