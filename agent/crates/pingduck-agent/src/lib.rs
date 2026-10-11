//! The PingDuck agent (docs/ROADMAP.md Phase 4).
//!
//! Starts unpaired and advertises itself on the LAN (SSDP plus a small HTTP
//! API on port 44480) until the app finds it and hands it a pairing code,
//! which it redeems directly with Supabase. Once paired it checks in every
//! minute and goes back to unpaired if the owner revokes it in the app.
//!
//! The wire contract (port, JSON shapes, error codes, UPnP description and
//! SSDP replies) is what the app expects: see
//! `pingduck_app/lib/features/agent/data/agent_lan_client.dart` and
//! `isPingDuckAgent` in `pingduck_app/lib/core/ffi/scanner_bridge.dart`.

pub mod agent;
pub mod config;
pub mod http;
pub mod log;
pub mod ssdp;
pub mod state;
pub mod supabase;
