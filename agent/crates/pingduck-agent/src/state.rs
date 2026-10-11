//! What the agent remembers across restarts: its instance id and, once
//! paired, its token. Kept in `<state dir>/agent.json` (mode 0600 on Unix;
//! on Windows the installer restricts %ProgramData%\PingDuck).

use std::fs;
use std::io::Write;
use std::path::{Path, PathBuf};
use std::sync::Mutex;

use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct State {
    /// UPnP UDN; lives as long as the state directory.
    pub instance_id: String,
    #[serde(default, skip_serializing_if = "String::is_empty")]
    pub agent_id: String,
    #[serde(default, skip_serializing_if = "String::is_empty")]
    pub network_id: String,
    /// Never logged, never sent over the LAN.
    #[serde(default, skip_serializing_if = "String::is_empty")]
    pub token: String,
}

impl State {
    pub fn paired(&self) -> bool {
        !self.token.is_empty()
    }
}

/// Thread-safe holder of the state, written through to disk on every change.
pub struct StateStore {
    path: PathBuf,
    state: Mutex<State>,
}

impl StateStore {
    /// Loads the file, or starts fresh with a new instance id. A corrupt file
    /// is kept as agent.json.bad rather than trusted or overwritten silently.
    pub fn open(dir: &Path) -> Self {
        let _ = fs::create_dir_all(dir);
        let path = dir.join("agent.json");
        let loaded = fs::read_to_string(&path).ok().map(|s| serde_json::from_str::<State>(&s));
        let state = match loaded {
            Some(Ok(s)) if !s.instance_id.is_empty() => s,
            Some(_) => {
                crate::log!("state: {} is unreadable; keeping it as agent.json.bad and starting unpaired", path.display());
                let _ = fs::rename(&path, path.with_extension("json.bad"));
                Self::fresh()
            }
            None => Self::fresh(),
        };
        let store = StateStore { path, state: Mutex::new(state) };
        if !store.path.exists() && !store.save(&store.get()) {
            crate::log!("state: cannot write {}; pairing will not survive a restart", store.path.display());
        }
        store
    }

    fn fresh() -> State {
        State { instance_id: uuid::Uuid::new_v4().to_string(), ..State::default() }
    }

    pub fn get(&self) -> State {
        self.state.lock().unwrap().clone()
    }

    /// Replaces the state and saves it. Returns false if the file could not
    /// be written; the in-memory state is updated either way.
    pub fn set(&self, s: State) -> bool {
        let mut guard = self.state.lock().unwrap();
        *guard = s;
        self.save(&guard)
    }

    /// Back to unpaired, keeping the instance id.
    pub fn clear_pairing(&self) -> bool {
        let mut guard = self.state.lock().unwrap();
        *guard = State { instance_id: guard.instance_id.clone(), ..State::default() };
        self.save(&guard)
    }

    /// Writes a temp file and renames it over the old one, so a crash
    /// mid-write never leaves a half-written token file.
    fn save(&self, s: &State) -> bool {
        let tmp = self.path.with_extension("json.tmp");
        let body = serde_json::to_string_pretty(s).unwrap_or_default() + "\n";
        let written = (|| -> std::io::Result<()> {
            let mut opts = fs::OpenOptions::new();
            opts.write(true).create(true).truncate(true);
            #[cfg(unix)]
            {
                use std::os::unix::fs::OpenOptionsExt;
                opts.mode(0o600);
            }
            let mut f = opts.open(&tmp)?;
            f.write_all(body.as_bytes())?;
            f.sync_all()?;
            drop(f);
            fs::rename(&tmp, &self.path)
        })();
        if written.is_err() {
            let _ = fs::remove_file(&tmp);
        }
        written.is_ok()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn round_trips_and_keeps_the_instance_id() {
        let dir = tempfile::tempdir().unwrap();
        let store = StateStore::open(dir.path());
        let id = store.get().instance_id;
        assert_eq!(id.len(), 36);
        assert!(store.set(State { token: "t".repeat(64), agent_id: "a".into(), ..store.get() }));
        let again = StateStore::open(dir.path());
        assert!(again.get().paired());
        assert_eq!(again.get().instance_id, id);
        assert!(again.clear_pairing());
        assert!(!StateStore::open(dir.path()).get().paired());
        assert_eq!(StateStore::open(dir.path()).get().instance_id, id);
    }

    #[cfg(unix)]
    #[test]
    fn token_file_is_private() {
        use std::os::unix::fs::PermissionsExt;
        let dir = tempfile::tempdir().unwrap();
        let store = StateStore::open(dir.path());
        store.set(State { token: "x".into(), ..store.get() });
        let mode = fs::metadata(dir.path().join("agent.json")).unwrap().permissions().mode();
        assert_eq!(mode & 0o777, 0o600);
    }

    #[test]
    fn a_corrupt_file_is_set_aside_not_trusted() {
        let dir = tempfile::tempdir().unwrap();
        fs::write(dir.path().join("agent.json"), "{not json").unwrap();
        let store = StateStore::open(dir.path());
        assert!(!store.get().paired());
        assert_eq!(store.get().instance_id.len(), 36);
        assert!(dir.path().join("agent.json.bad").exists());
    }

    #[test]
    fn uuids_are_v4_and_differ() {
        let (a, b) = (StateStore::fresh().instance_id, StateStore::fresh().instance_id);
        assert_ne!(a, b);
        assert_eq!(&a[14..15], "4");
    }
}
