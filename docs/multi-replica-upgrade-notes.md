# Multi-replica upgrade notes

Collected for the joint release; they move into UPGRADING.md then.

- **Upgrade everything together:** hbbs, hbbr, the api-server, the web client, this chart
  and the native clients. hbbs hands out one relay URL per hbbr pod
  (`wss://<publicHost>/ws/relay/<n>`); only this chart's web client routes those paths, and
  only the matching clients dial the relay hbbs hands out. A stock client with
  `relay-server` set fails with "Unknown relay server" unless the setting is exactly one of
  the handed-out URLs.
- **No plain `/ws/relay` and no shared hbbr Service.** Every relay path names its pod
  (`/ws/relay/<n>`), and clients only dial the relay hbbs hands out. Drop any fixed relay
  address: a client's `relay-server`, `webclient.env.RUSTDESK_RELAY` (the web client no
  longer reads it), or a proxy or script pointing at `/ws/relay` or `<fullname>-hbbr:21119`.
- **hbbs refuses to start without `RELAY_URLS`, or with an entry that is not a `ws://` or
  `wss://` URL.** The chart always sets valid ones; this matters only when overriding
  `RELAY_URLS` or running hbbs yourself. Clients dial only such URLs, and hbbs forwards only
  relays from its own list.
- **Changing `hbbr.replicas` can refuse a few sessions while hbbs rolls out.** The pods hold
  different relay lists until the rollout ends, so a session on a new relay URL that meets an
  hbbs pod without it fails with "Unknown relay server"; a retry after the rollout works.
- **`hbbs.relayAddress` is removed; use top-level `publicHost`.** Set it to the host
  clients use, without `:443` (keep another port, e.g. `rustdesk.example.com:8443`). The
  chart refuses to render while `hbbs.relayAddress` is set. hbbs hands out `wss://` URLs,
  or `ws://` when `apiserver.env.PUBLIC_URL` starts with `http://`.
- **hbbs and hbbr are StatefulSets.** The upgrade creates them and deletes the old
  Deployments; for a few seconds old and new pods run side by side and devices reconnect
  once. Scripts using `deploy/<fullname>-hbbs` or `deploy/<fullname>-hbbr` must use
  `statefulset/...`.
- **Stopping hbbr and web client pods drains sessions for up to 30 minutes**
  (`hbbr.terminationGracePeriodSeconds`, `webclient.terminationGracePeriodSeconds`,
  default 1800). A rollout of either can take replicas x that long; lower them for faster
  rollouts at the cost of cutting longer sessions.
- **Probes moved to `/livez` and `/readyz`** (hbbs port 21121, hbbr 21122, api-server its
  API port). hbbs also binds 21120 (internal), hbbr 21122. NetworkPolicies let hbbs pods
  reach each other on 21120 and hbbr's health port on 21122.
- **In-flight OIDC logins** on old api-server pods fail once during the upgrade.
- **Unflushed legacy address-book writes** on old api-server pods are dropped.
- **An hbbs rolling update takes about 20 s longer per pod** (`hbbs.minReadySeconds`, default 20): the next pod waits so moved devices outlast the client's 18 s reconnect throttle.
- **api-server migration 0014** (index on `audit_conn_ref.created_at`) briefly blocks audit-ref inserts while it builds.
- **api-server migration 0013** briefly locks the audit tables, and is one-way: back up the
  database first if you may need to roll back.
- **hbbs changes:** it refuses `-k <public key>` (it needs the keypair); `-r` is removed;
  `--mask` no longer swaps the relay to the pod's LAN address.
- **Native clients on raw TCP 21116 always relay.**
- **`KEEP_ALIVE_SECS` must stay below 30.**
- **`RELAY_URLS` must be `wss://` when the web client is served over https.** The chart derives it; this matters only if you override `RELAY_URLS` through `hbbs.env`, or set `PUBLIC_URL` to `http://` while the web client is served over https.
- **`hbbs.replicas` is at most 32.**
