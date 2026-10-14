# Shared recognition database (Phase 7, after launch)

Layer 3 of device recognition. Layers 1 and 2 are built: users can correct a
card, and each answer is remembered by the device's fingerprint and offered for
devices that look the same, all on the phone (`features/recognition/fingerprint.dart`,
the `learned_labels` table).

This layer pools those answers across accounts, which is how Fing names PCs by
model: from its users, not from the device.

## Decision: on by default, with a switch (2026-10-13)

Fing does the same. Its privacy policy says it collects "the originating public
IP address and the MAC addresses of the devices you submit to us for the
purpose of device recognition", and that "You also can turn off device
recognition at any time". The switch is called Device Recognition in its
settings.

We send less than Fing:

| | Fing | PingDuck |
| --- | --- | --- |
| Device MACs | Full | None. Only the vendor name the OUI resolves to |
| Public IP | Yes | Not stored (Supabase sees it on the request only) |
| Hostnames | Unknown | Only the shape, with names blanked (`*-iphone`) |
| Labels | Unknown | Only labels the user typed |

## What is sent

- **Looking up**, whenever recognition runs and the switch is on: the
  fingerprint string only.
- **Contributing**, only when the user saves a label: the fingerprint, the
  label (brand, model, OS) and the account id. The account id is used to count
  distinct accounts and is never returned to other users.

Anonymous users (no account) can look up but not contribute, so one person
can't vote many times without signing in.

## Server

```sql
create table recognition_votes (
  fingerprint text not null check (length(fingerprint) <= 1024),
  account_id  uuid not null references auth.users on delete cascade,
  brand text check (length(brand) <= 64),
  model text check (length(model) <= 128),
  os    text check (length(os) <= 64),
  voted_at timestamptz not null default now(),
  primary key (fingerprint, account_id)  -- one vote per account per fingerprint
);
```

- No client reads of `recognition_votes` (RLS denies select). Writes go through
  a `vote_recognition(fingerprint, brand, model, os)` RPC that upserts the
  caller's own row; an empty label deletes it.
- `recognize(fingerprints text[])` RPC returns, per fingerprint, the winning
  label when at least 3 distinct accounts voted and at least 2/3 of them agree
  (per field: brand, model and OS are tallied separately). Batch up to 256 per
  call.
- Optionally a materialized view refreshed by cron if the tally gets slow.

## App

- Settings → Device recognition switch, on by default (stored like
  `cloud_sync`). Off means no lookups and no contributions.
- A new confidence, `community`, below the user's own label and what the
  device says itself, above local guesses. Chip: COMMUNITY.
- Cache lookups in a table keyed by fingerprint for 7 days, so a scan doesn't
  call the server for devices it already asked about.
- Account deletion already cascades (`account_id` references `auth.users`).

## Before turning it on

- Privacy policy section on device recognition (what is sent, the switch).
- Play data safety: "Device or other IDs: no", "App activity → Other
  user-generated content: yes (labels), optional"; shared with no third party.
- Seed: our own test LAN labels, so the first users see some answers.

## Open questions

- Whether a learned label's fingerprint should also feed the vote, or only
  labels the user typed. (Proposed: only typed labels.)
- Abuse: one account can't move a label alone (3-account minimum). Rate-limit
  `vote_recognition` per account if spam shows up.
