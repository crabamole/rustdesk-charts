# Upgrading

Steps to take before or after `helm upgrade`, newest version first. Versions not
listed need nothing beyond the upgrade itself.

## 0.14.0

0.14.0 ships rustdesk-server 1.1.16-7, rustdesk-api 3.9.0 and web client / clients 1.5.0-6.

- **Device admission.** The chart has a `deviceAdmission.enabled` switch (default `false`; see README
  "Device admission"). `deviceAdmission.webhook.url` and `deviceAdmission.webhook.keySecret` set an
  admission webhook. Turn the switch on only after this upgrade is complete. Devices that are
  already registered stay admitted. Devices older than cRustDesk 1.5.0-6 are refused the same way
  but do not show "pending" or "rejected" on their home page.
- **rustdesk-api 3.9.0 adds migrations 0019 and 0020** and runs them at start. rustdesk-server
  1.1.16-7 writes the new `admission` column when a new device registers. Until rustdesk-api has
  migrated, hbbs answers a new device's registration with a server error, and the device tries
  again later. Devices that are already registered are not affected.
- **Viewers and devices 1.5.0-6 never run a session without end-to-end encryption.** A viewer
  refuses a device whose key it cannot verify, and a device refuses a viewer that sends no key.
  Older clients that use "Continue anyway" on a key warning are refused by 1.5.0-6 devices.

## 0.13.1

0.13.1 ships rustdesk-api 3.8.1: the console footer and tab title name this project and link
the source, upstream and the license. Nothing to do beyond the upgrade.

## 0.13.0

0.13.0 ships rustdesk-api 3.8.0 and web client / clients 1.5.0-4; rustdesk-server stays 1.1.16-6.

- **Upgrade viewers and devices to cRustDesk 1.5.0-4 together.** 1.5.0-4 sends viewer clipboard text
  to a device only when a program on the device reads the clipboard. With an older client on either
  side, pasting text into the device does not work.
- rustdesk-api 3.8.0 adds the clipboard text audit (`POST /api/audit/clipboard`, migration 0018) and a
  Clipboard tab in the console. It runs its migration at start; nothing else to do. 1.5.0-4 devices
  with an older api-server drop their clipboard records; 3.8.0 works with older clients, which send
  none.

## 0.12.0

0.12.0 ships rustdesk-server 1.1.16-6, rustdesk-api 3.7.0 and web client / clients 1.5.0-3. The matching
native clients are cRustDesk 1.5.0-3.

- **Upgrade the devices to cRustDesk 1.5.0-3 first.** rustdesk-api 3.7.0 accepts a device's own calls
  (heartbeat, system info, connection, file and alarm records) only when the device signs them with
  the key it registered with hbbs. cRustDesk 1.5.0-1 and earlier and stock RustDesk on devices get 401:
  no heartbeat answer (no policy, no console disconnect) and no audit records. 1.5.0-3 works with the
  0.11.0 servers, so upgrade the devices before `helm upgrade`. Viewers (the client variant) send no
  device calls and are not affected.
- **A device keeps its registered key.** hbbs 1.1.16-6 refuses another key for a known device ID from
  any address (before, it accepted one from the address of the last registration). A device that
  lost its configuration (an uninstall that removed it, a restored disk) keeps its ID and shows "This
  device's key changed". To let it register again, either:
  - its owner logs in on the device with "Log in to keep this ID" (the user of the device's last
    login, still logged in: a logout ends that), or
  - an admin resets the key: Devices page, "Reset key", or
    `kubectl exec deploy/<release>-apiserver -- /app/rustdesk-api peer reset-key <id>`.

  Clients before 1.5.0-2 log `unknown RegisterPkResponse` and stay offline until the reset.
- **The api-server adds the column `peer.approved_pk` when it starts (migration 0017); hbbs 1.1.16-6
  reads it.** The chart upgrades both together; outside the chart, upgrade the api-server first.
- **New, nothing to do:** the audit page disconnects a live connection and lists admin changes
  (console log); same-user access stays off until `apiserver.env.SAME_USER_ACCESS: "Y"`.
- **rustdesk-api 3.7.0 removes** `/api/software/releases`, `/api/software/download` and
  `/api/oidc/settings` (they answer 404; our clients do not call them), and users can no longer change
  their own email; admins still can.
- **The web client's pages refuse framing by other sites** (`X-Frame-Options: SAMEORIGIN`). A portal that
  shows the web client in an iframe from another origin must link to it instead.
- **PostgreSQL and the OIDC mock declare `runAsNonRoot`**, for namespaces at the restricted Pod Security
  level.
- **Web client 1.5.0-2:** while logged out, a login button takes the place of the remote ID field.
- **Clients list only their own devices.** `GET /api/peers` returns, for every user including admins,
  only the devices that user is logged in on; `GET /api/users` returns only the caller; device counts
  and CPU statistics are admin-only. The console uses the admin-only `/api/peer-list` and
  `/api/user-list`. A user of a stock client (which never records an owner) sees an empty device list.
  Scripts that used `/api/peers` or `/api/users` with an admin token to list everything must switch to
  `/api/peer-list` / `/api/user-list`.
- **Clients 1.5.0-3:** no automatic STUN/DNS lookups of public hosts in websocket mode; the device build
  no longer answers LAN discovery; `cRustDesk --password` enforces the UI's password rule.

## 0.11.0

Same images as 0.10.0 (rustdesk-server 1.1.16-5, rustdesk-api 3.6.0, web client 1.4.9-9).

- **The chart routes the OIDC mock** through `istio.gateway`, on the host of `oidcMock.authorizeUrl`
  (or `oidcMock.hosts` when a proxy in front rewrites `Host`). Delete a VirtualService you wrote for the
  mock before upgrading; the chart's has the same name.
- **`oidcMock.enabled` (default `true`) now requires `oidcMock.authorizeUrl`.** With your own IdP
  (`hbbs.oauth2.existingSecret`), set `oidcMock.enabled: false`; the install fails otherwise instead of
  deploying an unused mock.

## 0.10.0

0.10.0 ships rustdesk-server 1.1.16-5 and rustdesk-api 3.6.0 (web client 1.4.9-9 unchanged).
Clients reach hbbs, hbbr and the api-server through the Istio ingress gateway instead of the web
client's nginx (see [Exposing it](README.md#exposing-it)).

- **The api-server requires `PUBLIC_URL`** and no longer derives its origin from `Host` or
  `X-Forwarded-Host`. The chart sets it to `https://<publicHost>`; set `apiserver.env.PUBLIC_URL`
  if users open another origin (e.g. `http://` or another port). Outside the chart the api-server
  refuses to start without it.
- **Istio is required.** Set `istio.gateway` (`<namespace>/<name>` of your Gateway),
  `istio.gatewayPods` if the gateway pods are not `istio: ingressgateway` in `istio-system`
  (Helm merges the labels with that default: override the `istio` key too), and `trustedProxies`
  (CIDRs of the gateway pods, plus any proxy that appends to or overwrites `X-Forwarded-For`).
  The chart refuses to render without `istio.gateway` and `trustedProxies`.
- **List only hops that set `X-Forwarded-For` in `trustedProxies`:** the gateway pods and a CDN or
  L7 proxy. Never list a hop that only forwards TCP (L4 load balancer, NodePort/LoadBalancer
  Service with SNAT); use `externalTrafficPolicy: Local` or PROXY protocol so the gateway sees the
  client. It must not overlap any client network: keep it as narrow as the gateway pods' range
  (for example `10.244.0.0/16`).
- **Cutover order:**
  1. Check the gateway pods' labels (`kubectl get pod -n <ns> --show-labels`) and set
     `istio.gatewayPods` to match. The istio/gateway Helm chart labels its pods
     `istio: <release name>`, not `istio: ingressgateway`; with a wrong selector every request
     times out, because the NetworkPolicies admit only those pods.
  2. The chart's VirtualService is named after the release's full name (e.g. `rustdesk`) and
     routes `/ws/id`, `/ws/relay/<n>`, `/api/`, `/ui` and `/`. Delete a hand-written
     VirtualService for the same host right before `helm upgrade`: Helm refuses to adopt one of
     the same name, and two for one host merge unpredictably. Expect a brief outage.
  3. Run `helm upgrade`.
  4. Verify `/ws/id` and `/api/` through the public host.
  Rolling back to 0.9.0 needs the hand-written VirtualService re-applied.
- **`ingress`, `realIp`, `webclient.nginx` and `*.env.TRUSTED_PROXIES` are removed;** the chart
  fails if they are set. Use `trustedProxies`.
- **Upgrade the server and api-server images with the chart.** hbbs, hbbr and the api-server now
  read the client address from `X-Forwarded-For` only (never `X-Real-IP`); older images prefer
  `X-Real-IP`, which the gateway does not set.
- **Every pod gets `sidecar.istio.io/inject: "false"`**, and the web client serves static
  files only (no drain, default grace period).
- **Paged lists in rustdesk-api 3.6.0.** `/api/peers`, `/api/users` and `/api/groups` return pages
  (10 by default) with the real total and accept a `q` search; callers that expected every row in
  one response must page.
- **Quieter api-server logs (rustdesk-api 3.6.0):** one `access` line per request
  (`GET /api/peers 200 4ms`; no query string, no probes) instead of Rocket's debug output with
  the HTTP internals of every request. `apiserver.env.RUST_LOG` sets the filter; `serve
  --log_level` is gone.
- Clients need no change.

## 0.9.0

0.9.0 ships rustdesk-server 1.1.16-4, rustdesk-api 3.5.0 and web client 1.4.9-9. It runs hbbs,
hbbr, the api-server and the web client as several replicas (see
[Replicas and availability](README.md#replicas-and-availability)).

- **Upgrade everything together, native clients included (cRustDesk 1.4.9-9).** hbbs now hands
  out the relay, one URL per hbbr pod, and clients dial only that URL; older clients and older
  hbbs or api-server images do not work with this release.
- **Set `publicHost`; `hbbs.relayAddress` is gone.** `publicHost` is the host[:port] clients reach
  the web client through. hbbs hands out `wss://<publicHost>/ws/relay/<n>` (`ws://` when
  `apiserver.env.PUBLIC_URL` starts with `http://`). The plain `/ws/relay` route is removed.
- **Clients drop any fixed relay address.** Our clients no longer have a relay setting; stock
  clients must leave "Relay Server" empty. Running hbbs without the chart, set `RELAY_URLS` to
  `ws://` or `wss://` URLs; hbbs refuses to start otherwise.
- **hbbs and hbbr become StatefulSets.** Helm replaces the old Deployments, so devices reconnect
  and running sessions are cut once during this upgrade.
- **The api-server's database migrations are one-way** (0009–0014: login audit, hbbs presence,
  audit binding). Back up the database first if you may need to roll back.

## 0.8.0

0.8.0 ships rustdesk-api 3.4.0 and web client 1.4.9-8 (rustdesk-server 1.1.16-3 unchanged).

- **Native clients must be cRustDesk 1.4.9-8 or later.** Logins now hand their result only to the app or page that started them; cRustDesk 1.4.9-7 and earlier and stock RustDesk clients can no longer log in. Upgrade the clients together with the chart.
- **Audit rows name the viewer machine.** Connection records carry the viewer's hostname, OS and login address from its login (self-reported).
- **The api-server's database migration is one-way** (0008, viewer rows per machine and user). Back up the database first if you may need to roll back.

## 0.7.0

0.7.0 ships rustdesk-server 1.1.16-3, rustdesk-api 3.3.0 and web client 1.4.9-7.

- **The login dialog offers OIDC only.** Web client 1.4.9-7 and the cRustDesk 1.4.9-7
  native builds no longer show the username and password fields; the api-server
  never accepted password logins. Stock RustDesk clients still show them.
- **New Viewers list.** The console's Devices page lists machines that log in with the
  cRustDesk client build (view-only machines). Rows appear from their next login.
- **Set `realIp.trustedProxies` if a proxy sits in front of the web client** (the
  chart's own `ingress:`, an Ingress controller or a load balancer). The web client's
  nginx now replaces `X-Real-IP` and `X-Forwarded-For` with the address it resolves
  itself. With `realIp.trustedProxies` empty that is the front proxy's address, so
  every client is recorded with it and all clients share one registration rate
  limit (before, the front proxy's `X-Real-IP` passed through). Set
  `realIp.trustedProxies` to the front proxy's address range and `realIp.header` to
  the header it puts the client address in (default `X-Forwarded-For`). The release
  notes warn when `ingress.enabled` is true and the list is empty. See
  [Client addresses behind proxies](README.md#client-addresses-behind-proxies).
- **Upgrade the api-server and hbbs together.** hbbs now calls a new api-server
  endpoint to attribute connections to the controlling user; an older api-server
  still works (hbbs falls back automatically) but without that attribution. The
  api-server's migration also fixes existing file-transfer audit records that had
  the remote and local device swapped.
- **The api-server's database migration is one-way.** An older api-server image
  refuses to start on the migrated database (sqlx reports a missing migration).
  Back up the database first if you may need to roll back.

## 0.6.0

0.6.0 ships rustdesk-api 3.2.0 and web client 1.4.9-5.

- **The api-server's database migration is one-way.** rustdesk-api 3.2.0 changes the
  `strategy` table; an older api-server image refuses to start on the migrated
  database. Back up the database first if you may need to roll back.
- **Device policy.** The web console has a new Policy page that pushes permission
  settings to every device; nothing changes on devices until an admin saves a
  policy. See [Device policy](README.md#device-policy).
- **Only admins can use the web console.** Other users who sign in get a 403 page.
- **The OIDC mock's login button reads "OIDC"** (was "Dex"): its provider `op` is now
  `OIDC`. A client whose login dialog was open during the upgrade has to retry once.
  With `hbbs.oauth2.existingSecret` the label is your own `op`: set `op = "OIDC"` and
  `op_auth_string = "oidc/OIDC"` in your `oauth2.toml` for the same label, then
  restart the api-server (`kubectl rollout restart deploy/<fullname>-apiserver`);
  the chart restarts it only when it generates the provider file itself.
- **Ports in the OIDC callback URL are kept.** The web client's nginx forwards the
  client's `Host` with its port, so NodePort and other non-default ports work. Set
  `apiserver.env.PUBLIC_URL` if the api-server is reached through another host
  than the one users see; see [OIDC provider](README.md#oidc-provider).
- **Web client:** video shows without WebGL (with a notice), and audio plays again.

## 0.5.2

0.5.2 ships rustdesk-api 3.1.0 and web client 1.4.9-4.

- `rustdesk-api admin promote|demote` take the user's email; names are no longer
  accepted. See [Login and admins](README.md#login-and-admins).
- New `global.imagePullSecrets` for registries that need a login.
- The bundled PostgreSQL is pinned to `17.11-trixie`.

## 0.5.0

0.5.0 ships rustdesk-api 3.0.0 and web client 1.4.9-20260927-1. Breaking changes:

- **Login is OIDC-only.** Password login and the seeded `admin` user are gone (a
  database migration deletes it). Set `hbbs.oauth2.existingSecret` (your IdP) or
  `oidcMock.authorizeUrl`; see [OIDC provider](README.md#oidc-provider). Admins are promoted
  with the `rustdesk-api admin` CLI; see [Login and admins](README.md#login-and-admins).
- **Provider files need `issuer`** (except `Github`); ID tokens with another issuer,
  audience or an expired `exp` are rejected.
- **Users are identified by the OIDC `sub`.** Existing accounts are taken over by the
  first login whose email matches exactly one account without a `sub`.
- **Logins finished in another browser than they started in need confirmation.**
  Native clients show an Approve/Deny page after the IdP login.
- `hbbs.relayAddress` is required; `hbbr.replicas` and `webclient.env.RUSTDESK_KEY`
  are rejected (the web client reads the key from the keypair Secret, which is now
  checked at install time).
- `LOGGED_IN_ONLY` defaults to `Y`; NetworkPolicies are on by default.

## 0.3.0 (from 0.2.x)

This is a breaking change. 0.2.x stored hbbs state in a SQLite database on a
persistent volume; 0.3.0 requires PostgreSQL and removes the hbbs PVC
(`hbbs.persistence`), `apiserver.enabled`, and the per-component
`databaseUrl`/`databaseUrlSecretName` values. Setting `postgresql.persistence.size`
after the first install has no effect — the StatefulSet's `volumeClaimTemplates`
are immutable, so update it in your values file before the first 0.3.0 install.

Data is **not** migrated automatically. hbbs runs its SQLite database in WAL
mode, so committed transactions can sit in `db_v2.sqlite3-wal` instead of the
main file — back up all three files from the hbbs pod (with hbbs stopped or
quiesced) before upgrading if you need to keep existing peer/user records:

```bash
kubectl cp <namespace>/<hbbs-pod>:/data/db_v2.sqlite3 ./db_v2.sqlite3
kubectl cp <namespace>/<hbbs-pod>:/data/db_v2.sqlite3-wal ./db_v2.sqlite3-wal
kubectl cp <namespace>/<hbbs-pod>:/data/db_v2.sqlite3-shm ./db_v2.sqlite3-shm
```
