//! pingduck-agent: see the crate docs in lib.rs.
//!
//! The scan loop and agent_sync reporting arrive with the Agent daemon ticket.

use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
use std::time::{Duration, Instant};

use pingduck_agent::agent::{Agent, Heartbeat};
use pingduck_agent::config::Config;
use pingduck_agent::http::{self, Handler};
use pingduck_agent::ssdp;
use pingduck_agent::state::StateStore;
use pingduck_agent::supabase::HttpSupabaseClient;

#[cfg(windows)]
mod winsvc;

const HEARTBEAT_EVERY: Duration = Duration::from_secs(60);

const USAGE: &str = "usage: pingduck-agent [--version]
Runs the agent in this console. Configure with PINGDUCK_* environment variables.
Windows (as administrator):
  pingduck-agent install             register and start the PingDuckAgent service
  pingduck-agent uninstall [--purge] remove the service (--purge also deletes its pairing)";

fn version() -> String {
    format!("{} (core {})", env!("CARGO_PKG_VERSION"), pingduck_core_sys::version())
}

/// Runs the agent until `stop` is set.
pub(crate) fn run(stop: Arc<AtomicBool>) {
    let config = Config::from_env();
    let store = Arc::new(StateStore::open(&config.state_dir));
    let supabase = Arc::new(HttpSupabaseClient::new(&config.supabase_url, &config.supabase_key));
    let started = Instant::now();
    let agent = Arc::new(Agent::new(
        config.clone(),
        store.clone(),
        supabase,
        env!("CARGO_PKG_VERSION").into(),
        Box::new(move || started.elapsed().as_millis() as i64),
    ));

    let state = store.get();
    pingduck_agent::log!(
        "pingduck-agent {} \"{}\" (instance {}), {}",
        version(),
        config.name,
        state.instance_id,
        if state.paired() { "paired" } else { "waiting to be added in the app" }
    );
    if !state.paired() && !config.pairing_code.is_empty() {
        pingduck_agent::log!("pair: redeeming PINGDUCK_PAIRING_CODE");
        agent.claim(&config.pairing_code);
    }

    let handler: Handler = {
        let agent = agent.clone();
        Arc::new(move |req, peer| agent.handle(req, peer))
    };
    let http = {
        let (stop, port) = (stop.clone(), config.http_port);
        std::thread::spawn(move || {
            if let Err(e) = http::serve(port, handler, stop) {
                pingduck_agent::log!(
                    "http: cannot listen on port {port} ({e}); the app will not find this agent \
                     (set PINGDUCK_HTTP_PORT, or pair with PINGDUCK_PAIRING_CODE)"
                );
            }
        })
    };
    let ssdp = {
        let (stop, port, id) = (stop.clone(), config.http_port, state.instance_id.clone());
        std::thread::spawn(move || {
            if let Err(e) = ssdp::run(&id, env!("CARGO_PKG_VERSION"), port, &stop) {
                pingduck_agent::log!(
                    "ssdp: cannot use port 1900 or join the multicast group ({e}); the app will not find this \
                     agent by itself (is the container on --net=host?). PINGDUCK_PAIRING_CODE still works."
                );
            }
        })
    };

    // Heartbeat once a minute while paired. After a network error, retry on
    // the next tick and keep the pairing.
    let mut next_beat = Instant::now();
    let mut warned = false;
    while !stop.load(Ordering::Relaxed) {
        if Instant::now() >= next_beat {
            match agent.heartbeat() {
                Heartbeat::Error if !warned => {
                    pingduck_agent::log!("heartbeat: Supabase unreachable; will keep trying");
                    warned = true;
                }
                Heartbeat::Error => {}
                _ => warned = false,
            }
            next_beat = Instant::now() + HEARTBEAT_EVERY;
        }
        std::thread::sleep(Duration::from_millis(250));
    }

    pingduck_agent::log!("stopping");
    let _ = ssdp.join();
    let _ = http.join();
}

fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();
    match args.first().map(String::as_str) {
        None => {}
        Some("--version" | "-v") => {
            pingduck_agent::log!("pingduck-agent {}", version());
            return;
        }
        #[cfg(windows)]
        Some("service") => {
            if let Err(e) = winsvc::run_service() {
                eprintln!("not started by the service manager ({e}); use `pingduck-agent install`");
                std::process::exit(1);
            }
            return;
        }
        #[cfg(windows)]
        Some(cmd @ ("install" | "uninstall")) => {
            let result =
                if cmd == "install" { winsvc::install() } else { winsvc::uninstall(args.iter().any(|a| a == "--purge")) };
            if let Err(e) = result {
                eprintln!("{cmd} failed: {e}");
                std::process::exit(1);
            }
            return;
        }
        Some(_) => {
            eprintln!("{USAGE}");
            std::process::exit(2);
        }
    }

    let stop = Arc::new(AtomicBool::new(false));
    let s = stop.clone();
    if let Err(e) = ctrlc::set_handler(move || s.store(true, Ordering::Relaxed)) {
        eprintln!("cannot install the stop handler: {e}");
    }
    run(stop);
}
