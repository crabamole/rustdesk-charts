# rustdesk-charts

Helm charts for deploying RustDesk OSS server components, using forked images that enable web client and WebSocket support.

## Components

| Component | Container Image | Source Repo | Description |
|-----------|----------------|-------------|-------------|
| hbbs | `ghcr.io/crabamole/rustdesk-server` | [crabamole/rustdesk-server](https://github.com/crabamole/rustdesk-server) | Rendezvous server |
| hbbr | `ghcr.io/crabamole/rustdesk-server` | [crabamole/rustdesk-server](https://github.com/crabamole/rustdesk-server) | Relay server |
| web-client | `ghcr.io/crabamole/rustdesk/web-client` | [crabamole/rustdesk](https://github.com/crabamole/rustdesk) | Browser-based remote desktop client |
| api-server | `ghcr.io/crabamole/rustdesk-api` | [crabamole/rustdesk-api](https://github.com/crabamole/rustdesk-api) | REST/OIDC API server, owns the database schema |

## Why forked images?

The RustDesk web client and WebSocket-based peer registration were [removed from the upstream OSS builds](https://github.com/rustdesk/rustdesk) and are now only available in RustDesk Server Pro. The forked repos restore these features for the OSS server:

- [crabamole/rustdesk](https://github.com/crabamole/rustdesk) — restores the web client with OSS server compatibility patches
- [crabamole/rustdesk-server](https://github.com/crabamole/rustdesk-server) — enables WebSocket peer registration for web client connectivity

## Prerequisites

### Istio

Clients reach the servers through an existing Istio ingress gateway (see [Exposing it](#exposing-it)).
The chart only needs the `networking.istio.io/v1beta1` VirtualService API; it is tested on Istio 1.16.7.

### Generate keypair

The chart requires a Kubernetes secret containing the hbbs keypair. hbbs signs with it and the web client reads the public key from it, so there is no key to copy into values. When installing against a cluster, the chart checks that the Secret exists, has both keys, and that the public key belongs to the private key. Back the Secret up: every client trusts this key, and losing it means re-keying them all.

```bash
# Generate keypair
output=$(docker run --rm --entrypoint /usr/local/bin/rustdesk-utils \
  ghcr.io/crabamole/rustdesk-server:1.1.16-5 genkeypair)
public_key=$(echo "$output" | grep 'Public Key:' | awk '{print $3}')
secret_key=$(echo "$output" | grep 'Secret Key:' | awk '{print $3}')

# Create Kubernetes secret
kubectl create namespace rustdesk --dry-run=client -o yaml | kubectl apply -f -
kubectl create secret generic rustdesk-keypair \
  --from-literal=id_ed25519.pub="$public_key" \
  --from-literal=id_ed25519="$secret_key" \
  -n rustdesk

# Save the public key: native clients need it
echo "$public_key"
```

## Usage

```bash
helm install rustdesk ./charts -n rustdesk -f values-override.yaml
```

Create a `values-override.yaml` with your deployment-specific settings:

```yaml
# Required: the host clients reach the web client through (add :<port> if not 443).
publicHost: "rustdesk.example.com"

# Required: the Istio Gateway and the CIDRs of its pods (see "Exposing it").
istio:
  gateway: istio-ingress/public
trustedProxies:
  - 192.0.2.0/24

# Quickstart only: the bundled OIDC mock, reachable by browsers at this URL.
# For production, disable it and use your IdP (see "OIDC provider").
oidcMock:
  authorizeUrl: "https://oidc.example.com"
```

## Images

The chart's default images:

| Image | Used by |
|-------|---------|
| `ghcr.io/crabamole/rustdesk-server:1.1.16-5` | hbbs, hbbr |
| `ghcr.io/crabamole/rustdesk-api:3.6.0` | api-server |
| `ghcr.io/crabamole/rustdesk/web-client:1.4.9-9` | web client |
| `docker.io/library/postgres:17.11-trixie` | bundled PostgreSQL (`postgresql.enabled`) |
| `ghcr.io/rophy/oidc-mock:20260913-34fdbaf` | OIDC mock (`oidcMock.enabled`) |

`global.imageRegistry` and `global.imagePullSecrets` apply to all of them.

The native client installers for the same release are in `ghcr.io/crabamole/rustdesk/installers:1.4.9-9`
(not deployed by the chart; see the rustdesk [install guide](https://github.com/crabamole/rustdesk/blob/master/docs/crustdesk-install.md)).

## Exposing it

Clients reach the chart through an Istio Gateway that the platform owns (listener, TLS
certificate, gateway pods); the chart never creates it. It renders one VirtualService bound to
that Gateway. The minimal values:

```yaml
publicHost: rustdesk.example.com
istio:
  gateway: istio-ingress/public   # <namespace>/<name> of the Gateway
trustedProxies:                   # the gateway pods, and proxies that set X-Forwarded-For
  - 192.0.2.0/24
```

The VirtualService matches `publicHost` (any `:port` stripped) and routes:

| Path | Backend |
|------|---------|
| `/ws/id` | hbbs:21118 (WebSocket) |
| `/ws/relay/<n>` | hbbr pod `<n>`:21119 (WebSocket), one exact path per pod |
| `/api/`, `/ui` | api-server |
| `/` | web client (static files) |

- `istio.hosts` replaces the hosts to match; set it when a proxy in front rewrites `Host`.
- `istio.requestHeaders` sets headers on every route, e.g. `x-forwarded-proto: https` behind a
  plain-HTTP gateway listener.
- Every route removes a client-supplied `X-Real-IP`.
- Istio leaves route and stream idle timeouts off, so open WebSockets are not cut and nothing
  needs raising.
- Changing `hbbr.replicas` changes only the VirtualService and hbbs's relay URLs.

`ingress` and `realIp` are removed; the chart fails if either is set.

### Client settings and ports

Clients reach everything through that one host, so their WebSocket URLs are
`wss://<host>/ws/id` and, for relayed sessions, the `wss://<host>/ws/relay/<n>` URL hbbs
hands out (or `ws://` on port 80):

- Set `custom-rendezvous-server` to `<host>` **without a port** and `api-server` to
  `https://<host>`. The relay is always the one hbbs hands out: cRustDesk has no relay
  setting; on stock clients leave `relay-server` empty.
- hbbs hands out `wss://` URLs. For a plain-HTTP service set `apiserver.env.PUBLIC_URL`
  to `http://<host>`; hbbs then hands out `ws://` ones.
- Stock RustDesk clients only use WebSocket on 443 (wss, chosen by an `https` api-server)
  or 80 (ws), and drop any other port. Writing `<host>:443` as the rendezvous server
  makes them send relayed sessions to `/ws/id`, so those sessions fail.
- The [cRustDesk builds](https://github.com/crabamole/rustdesk) also support another
  port `P`: set `custom-rendezvous-server` to `<host>:P`, `api-server` to
  `http(s)://<host>:P`, and `publicHost` to `<host>:P`; all three must carry
  the same port.

The api-server builds its OIDC callback URL from `PUBLIC_URL`, never from request headers.
The chart sets it to `https://<publicHost>`; if users open another origin (another
scheme or port), set it explicitly:

```yaml
apiserver:
  env:
    PUBLIC_URL: https://rustdesk.example.com
```

## Replicas and availability

hbbs, hbbr, the api-server and the web client each scale with `replicas` (`hbbs.replicas`,
`hbbr.replicas`, `apiserver.replicas`, `webclient.replicas`; default 1). With two or more of
each, losing a pod or draining a node does not take remote access down:

- **hbbs** (StatefulSet, at most 32 pods): each device keeps one connection to one pod. The
  pods record in Postgres which pod holds which device and pass session setup to that pod
  over an internal port (21120). Devices on a lost pod reconnect to another within about 30 s.
- **hbbr** (StatefulSet): hbbs hands out one URL per pod, `wss://<publicHost>/ws/relay/<n>`,
  and the Istio gateway routes each to its pod, so both halves of a session meet there. hbbs
  hands out only pods whose `/readyz` answers.
- **api-server** (Deployment): keeps no state of its own.
- **web client** (Deployment): serves the static files only; it holds no sessions.

Rolling updates replace one pod at a time:

| Component | During its update |
|-----------|-------------------|
| hbbs | Devices on the stopping pod reconnect at once to the others; running sessions are not affected. The next pod is only updated once the previous one has been Ready for `hbbs.minReadySeconds` (default 20 s), so devices that moved to it outlast the client's 18 s reconnect throttle. |
| hbbr | The stopping pod takes no new sessions and relays its running ones until they end or `hbbr.terminationGracePeriodSeconds` (default 1800 s) runs out; those viewers then reconnect. Updating every pod can take replicas x the grace period. |
| api-server | On SIGTERM it fails `/readyz` but keeps serving until no request has arrived for 5 s (at most 25 s), so the Service and the gateway move on before it stops; then it finishes in-flight requests. |
| web client | Default 30 s grace period; nothing to drain. |

hbbs serves `/livez` and `/readyz` on port 21121, hbbr on 21122, the api-server on its API
port. A pod whose `/readyz` fails leaves the Service; that happens only while it shuts down. A
database outage does not make pods unready: every pod shares the database, so hbbs keeps its
devices and the api-server answers requests with fast errors until it is back. One whose `/livez`
fails is restarted.

With two or more replicas a component gets a PodDisruptionBudget (one pod down at a time).
Pods of each component are spread over nodes when the scheduler can (`ScheduleAnyway`).
hbbs registration limits and hbbr bandwidth limits apply per pod, so the effective limit is
the setting times the number of pods.

On SIGTERM hbbs keeps serving until no new connection has arrived for 2 s (at most 15 s), so the
Service and the gateway have moved on before it closes its device connections; devices then
reconnect to another pod. hbbr waits at least 10 s after SIGTERM
before it can exit, so a `hbbr.terminationGracePeriodSeconds` under 10 always ends in a kill; keep it at least 15 for margin.

If an hbbr pod's node is lost without the connection being reset, native clients and devices time
out on their own within about 30 s, and the web client within 12 s; each then reconnects through
another relay. The gateway sets no idle timeouts, so it keeps the dead connection until its TCP
retransmissions give up; that costs a socket, not the session.

### Sizing

Every device keeps one WebSocket open through the Istio gateway, and every session adds two
more (viewer and device to hbbr), one per side. Sizing the gateway for that many connections is
up to whoever runs it. Restarting a gateway pod drops every connection through it once its drain
(Istio default 5 s) ends; devices reconnect as they do when an hbbs pod stops. Raise
`hbbs.resources` memory with the fleet: the defaults are sized for a few hundred devices.

When an hbbs pod stops, all of its devices register again on the other pods within about a
second, and each registration reads and writes Postgres. Measured rolling restarts of hbbs
(two pods each):

| Devices | `postgresql.resources.limits.cpu` | Devices unreachable for at most |
|---|---|---|
| 200 | 1 (default) | 0.5 s |
| 5000 | 1 (default) | 7-8.5 s (Postgres throttled) |
| 5000 | 2 | 3-3.5 s (same without a limit) |

hbbs queues up to 4096 pending connections, capped by `net.core.somaxconn` in the pod (4096 on
current kernels).

## Network policies and service account

By default the chart adds ingress-only NetworkPolicies: Postgres accepts only hbbs
and the api-server; the api-server only the gateway pods and hbbs; hbbs and hbbr the
gateway pods on their WebSocket ports, plus hbbs pods on hbbs's internal port (21120) and
hbbr's health port (21122); the web client the gateway pods. The OIDC mock accepts any source.
The gateway pods are selected by `istio.gatewayPods` (namespace, default `istio-system`, and
pod labels, default `istio: ingressgateway`). Helm merges `istio.gatewayPods.labels` with that
default, so for other labels also override the `istio` key (set `istio: null` to drop it).
Egress is not restricted. Kubelet probes come from the pod's own node, which NetworkPolicy does
not block. Disable with `networkPolicy.enabled: false`; they need a CNI that enforces
NetworkPolicy (Calico, Cilium, ...).

All pods run under one ServiceAccount with no API token mounted (none of them
talks to the Kubernetes API). Set `serviceAccount.create: false` and
`serviceAccount.name` to use an existing one.

## Service mesh (Istio)

The chart sets `sidecar.istio.io/inject: "false"` on every pod (hbbs, hbbr, the api-server, the
web client, Postgres, the OIDC mock), so the gateway reaches them in plain text. A `podAnnotations`
value for that key wins. Do not add a `DestinationRule` that forces `ISTIO_MUTUAL` for these hosts:
there is no sidecar to terminate it, and the connection fails. With STRICT mTLS, inject all of
the components or none of them, since a pod with a sidecar refuses plain connections from pods
without one.

## Client addresses behind proxies

hbbs, hbbr and the api-server read the client address from `X-Forwarded-For` only; `X-Real-IP`
is never read. The chart sets `TRUSTED_PROXIES` on all three from `trustedProxies`:

1. A connection from a peer outside `trustedProxies` is the client; its headers are ignored.
2. Otherwise `X-Forwarded-For` is walked from the right, skipping addresses in `trustedProxies`;
   the first other address is the client.

`trustedProxies` lists CIDRs. Include only hops that append to or overwrite `X-Forwarded-For`:
the gateway pods, and a CDN or L7 proxy that sets it. Never list a hop that only forwards TCP (an
L4 load balancer, or a NodePort/LoadBalancer Service with SNAT); make the gateway see the client
instead, with `externalTrafficPolicy: Local` or PROXY protocol. `trustedProxies` must not overlap
any client network: keep it as narrow as the gateway pods' range (for example `10.244.0.0/16`).
An empty list trusts no peer, so every client would be recorded as the
gateway; the chart refuses to render without it. `*.env.TRUSTED_PROXIES` is rejected: use
`trustedProxies`.

## OIDC provider

Login is OIDC-only. For production, disable the mock and give the api-server your
IdP in an `oauth2.toml` stored in a Secret (key `oauth2.toml`):

```toml
[[provider]]
provider = "Oauth2"          # generic OIDC: Azure AD, Okta, Keycloak, Google, ...
authorization_url = "https://login.example.com/oauth2/v2.0/authorize"
token_exchange_url = "https://login.example.com/oauth2/v2.0/token"
app_id = "<client id>"
app_secret = "<client secret>"
scope = "openid email profile"
op = "OIDC"                  # login button label ("Sign in with OIDC"), sent back by clients
op_auth_string = "oidc/OIDC" # must be "oidc/<op>"
issuer = "https://login.example.com/<tenant>/v2.0"  # the IdP's issuer URL
```

- `provider`: `Oauth2` (sends the client secret both as HTTP Basic and in the
  form body), `Dex` (HTTP Basic only) or `Github`. Other names in the code
  (`Azure`, `Okta`, ...) are not implemented and are rejected; use `Oauth2`.
- `op` is the label of the login button in the web console ("Sign in with OIDC")
  and in the clients ("Continue with OIDC"); letter case is kept.
- `scope` must include `openid`: users are identified by the ID token's `sub`.
  `name` (else `preferred_username`) and `email` are only shown, never used to
  match accounts.
- `issuer` is required (except for `Github`): it must equal the `iss` claim of the
  IdP's ID tokens, i.e. the `issuer` in its `/.well-known/openid-configuration`.
  ID tokens with another issuer, another audience than `app_id`, or an expired
  `exp` are rejected.
- Register `<PUBLIC_URL>/api/oidc/callback` as the redirect URI (by default
  `https://<publicHost>/api/oidc/callback`).
- If the IdP's certificate comes from a private CA, add it with `extraCACerts`.

```bash
kubectl create secret generic corp-oidc -n rustdesk --from-file=oauth2.toml
helm upgrade --install rustdesk ./charts -n rustdesk -f values-override.yaml \
  --set oidcMock.enabled=false --set hbbs.oauth2.existingSecret=corp-oidc
```

The chart refuses to install without an OIDC configuration, and the api-server
refuses to start if the file is invalid. To check the file and that the IdP's
token endpoint is reachable (DNS, network, TLS) from the pod:

```bash
kubectl exec -n rustdesk deploy/rustdesk-apiserver -- /app/rustdesk-api oidc check --file /data/oauth2.toml
```

## Login and admins

Login is OIDC-only: the api-server stores no passwords and `POST /api/login`
always returns 401. Nobody is admin until an operator promotes them with the
api-server's CLI, which works directly on the database and takes the user's email
(the ID token's `email` claim; case-insensitive):

```bash
# the user must have logged in through OIDC once (that creates the account)
kubectl exec -n rustdesk deploy/rustdesk-apiserver -- /app/rustdesk-api admin promote alice@example.com
kubectl exec -n rustdesk deploy/rustdesk-apiserver -- /app/rustdesk-api admin demote alice@example.com
```

The first OIDC login creates an active, non-admin account
(`apiserver.env.OAUTH2_CREATE_USER: "1"`, the default), so anyone your IdP lets
through this client can use RustDesk. Limit access with the IdP's user or group
assignment for the client. Set it to `"0"` to create new accounts disabled until an
admin activates them on the web console's Users page.

Users whose IdP sends no email cannot be promoted, and an email shared by several
users is refused. Upgrading an existing install removes
the old built-in `admin` account (its password was public); the first user you
promote takes over its shared address books.

Starting a connection also requires being logged in: hbbs runs with
`LOGGED_IN_ONLY=Y` by default and checks the client's session with the api-server,
so a client that never logs in cannot connect to anyone. This applies to both
direct and relayed connections, including switch sides (refused the same way as
punch hole). (Devices registering to be controlled do not need to log in.) Set
`hbbs.env.LOGGED_IN_ONLY: "N"` to allow anonymous connections.

Upstream native clients still show username/password fields; logins through them
always fail. Use "Continue with ..." instead.

## Device policy

Admins set the permission settings of every device on the webconsole's **Policy** page
(keyboard, clipboard, file transfer, file copy and paste, audio, camera, terminal, TCP tunneling, remote
restart, recording, blocking input, privacy mode, remote printer, remote configuration
changes, permission type). Devices that use this server's API pick up a change on their
next heartbeat, within about 15 seconds.

- **Not managed** leaves the device's own setting; **Device default** resets it to the
  client's built-in default.
- As in RustDesk Pro, a user can change a setting locally after it arrives. Saving the
  policy again, **Re-push to all devices**, or
  `kubectl exec -n rustdesk deploy/rustdesk-apiserver -- /app/rustdesk-api policy repush`,
  sends the policy again and reverts such changes.
- The policy restricts what a device allows when someone connects to it; it does not
  limit what its user can do on other machines.

## Database

hbbs and the api-server run as separate pods sharing one PostgreSQL database. The
api-server creates and migrates the schema on startup; hbbs waits for it to be
ready before serving.

**Default (evaluation, small installs):** bundled single-instance PostgreSQL
(`postgresql.enabled=true`), no HA or backups.

**Production:** use an external managed PostgreSQL (backups and HA are its job) and disable the bundled one:

```yaml
postgresql:
  enabled: false

database:
  url: "postgres://user:pass@host:5432/db?sslmode=require"
  # or, to source the URL from an existing Secret instead:
  # existingSecret: my-database-secret
  # existingSecretKey: url
```

The bundled PostgreSQL's password is generated on first install and kept on
upgrade using `lookup`, which requires a live cluster. When rendering offline
(`helm template`, Argo CD, etc.), set `postgresql.auth.password` (must be
URL-safe — it's embedded in the connection URL) or
`postgresql.auth.existingSecret` instead of relying on generation.

`MAX_DATABASE_CONNECTIONS` defaults to `10` for hbbs and `20` for the
api-server (`hbbs.env.MAX_DATABASE_CONNECTIONS`, `apiserver.env.MAX_DATABASE_CONNECTIONS`).

The api-server logs one `access` line per request (no query string; probes skipped) plus its own
events. `apiserver.env.RUST_LOG` replaces the default filter `info,rocket=warn`;
e.g. `info,access=off` drops the access lines.

| Value | Description | Default |
|-------|-------------|---------|
| `postgresql.enabled` | Deploy the bundled single-instance PostgreSQL | `true` |
| `postgresql.auth.username` | Bundled database username | `rustdesk` |
| `postgresql.auth.database` | Bundled database name | `rustdesk` |
| `postgresql.auth.password` | Bundled database password (generated if empty; needs a live cluster) | `""` |
| `postgresql.auth.existingSecret` | Existing Secret (key `password`) for the bundled database, skips generation | `""` |
| `postgresql.persistence.size` | PVC size for the bundled database | `8Gi` |
| `database.url` | External database connection URL (used only when `postgresql.enabled=false`) | `""` |
| `database.existingSecret` | Existing Secret holding the full external database URL | `""` |
| `database.existingSecretKey` | Key in `database.existingSecret` holding the URL | `url` |
| `apiserver.port` | api-server container listen port (the Service port is fixed at `21114`) | `21114` |

### Uninstalling and rolling back

`helm uninstall` and `helm rollback` (e.g. back to a 0.2.x release) do **not**
delete two things that `helm install`/`helm upgrade` created:

- the bundled database's PVC, `data-<fullname>-postgresql-0` (from the
  StatefulSet's `volumeClaimTemplates`);
- the generated password Secret, `<fullname>-postgresql`, which is
  annotated `helm.sh/resource-policy: keep` specifically so it survives.

They're kept together on purpose: the next `helm install` re-adopts the kept
Secret and reuses the same password, so it still matches the password already
written into the surviving PGDATA on the PVC. If only one of the two were
kept, the reinstalled database would reject the (new or old) password and
hbbs/api-server would crash-loop on auth failures.

Consequences:
- Setting `postgresql.auth.password` to a new value after the first install
  does **not** change the database's password — it's only used the first time
  the Secret is created. The bundled Postgres keeps whatever password it was
  initialized with.
- To fully reset the bundled database (fresh data, new generated password),
  delete both the PVC and the Secret before the next install:

```bash
kubectl delete pvc data-<fullname>-postgresql-0 -n <namespace>
kubectl delete secret <fullname>-postgresql -n <namespace>
```

(`<fullname>` is normally `<release>` when the release name already contains
`rustdesk`, or `<release>-rustdesk` otherwise — see `rustdesk.fullname` in
`templates/_helpers.tpl`, or run `helm template` and check the object names.)

## Disaster recovery

Not verified yet. Durable state is Postgres, the keypair Secret and the OIDC provider
Secret; which device is on which hbbs pod is rebuilt as devices reconnect. A standby site
needs:

- a replica of the database (your provider's replication), used as an external database
  (`postgresql.enabled: false`, `database.url` pointing at the replica);
- the same keypair Secret and OIDC provider Secret;
- the same `publicHost`, with the IdP redirect URI on it;
- the chart installed with the same values, without `--wait`, then scaled to zero (the
  api-server crash-loops against the read-only replica until it is scaled down):

```bash
kubectl scale -n <namespace> statefulset/<fullname>-hbbs statefulset/<fullname>-hbbr \
  deploy/<fullname>-apiserver deploy/<fullname>-webclient --replicas=0
```

To fail over, promote the replica, run `helm upgrade` with the same values (it restores the
replica counts), and point DNS at the standby. Devices register with it when their
connections drop; users log in again only if their sessions had not been replicated yet.

## Upgrading

Version-specific steps are in [UPGRADING.md](UPGRADING.md).
