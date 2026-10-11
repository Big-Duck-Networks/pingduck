# Security

PingDuck scans home networks, and its agent runs around the clock with raw
network access, so we take reports seriously.

## Reporting a vulnerability

Please **don't open a public issue**. Instead, either:

- use GitHub's private reporting: **Security › Report a vulnerability** on this repository, or
- email **support@pingduck.app** with "Security" in the subject.

Include what you found, how to reproduce it, and what an attacker could do with
it. We'll acknowledge within 3 days and keep you posted until it's fixed. We're
happy to credit you once a fix ships, if you'd like.

## In scope

- The PingDuck Agent (`agent/`), including its LAN API on port 44480, SSDP, pairing and the Windows service
- The scanning engine (`core/`), especially its packet parsers
- The app (`pingduck_app/`) and the Windows installer (`installer/`)
- The database schema, row-level security and RPCs (`supabase/`)

## Out of scope

- Denial of service against your own network or devices
- Findings that need physical access to an unlocked device
- The publishable Supabase key in the app: it's public by design, and
  row-level security decides what it can do
