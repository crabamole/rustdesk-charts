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

### Generate keypair

The chart requires a Kubernetes secret containing the hbbs keypair. hbbs signs with it and the web client reads the public key from it, so there is no key to copy into values. When installing against a cluster, the chart checks that the Secret exists, has both keys, and that the public key belongs to the private key. Back the Secret up: every client trusts this key, and losing it means re-keying them all.

```bash
# Generate keypair
output=$(docker run --rm --entrypoint /usr/local/bin/rustdesk-utils \
  ghcr.io/crabamole/rustdesk-server:1.1.16-1 genkeypair)
public_key=$(echo "$output" | grep 'Public Key:' | awk '{print $3}')
secret_key=$(echo "$output" | grep 'Secret Key:' | awk '{print $3}')

# Create Kubernetes secret
kubectl create namespace rustdesk --dry-run=client -o yaml | kubectl apply -f -
kubectl create secret generic rustdesk-keypair \
  --from-literal=id_ed25519.pub="$public_key" \
  --from-literal=id_ed25519="$secret_key" \
  -n rustdesk

# Save the public key — needed for client configuration and RUSTDESK_KEY
echo "$public_key"
```

## Usage

```bash
helm install rustdesk ./charts -n rustdesk -f values-override.yaml
```

Create a `values-override.yaml` with your deployment-specific settings:

```yaml
hbbs:
  # Required: public host:port clients reach hbbr through.
  relayAddress: "rustdesk.example.com:443"

# Quickstart only: the bundled OIDC mock, reachable by browsers at this URL.
# For production, disable it and use your IdP (see "OIDC provider").
oidcMock:
  authorizeUrl: "https://oidc.example.com"
```

## Exposing it

Everything goes through the web client Service (port 80): it serves the web app and
routes `/ws/id`, `/ws/relay`, `/api` and `/ui` itself. So exposing the chart takes a
single rule sending your host to that Service; set `hbbs.relayAddress` to
`<host>:443`. The chart can create an Ingress for you, for example with
ingress-nginx and cert-manager:

```yaml
ingress:
  enabled: true
  className: nginx
  host: rustdesk.example.com
  tls:
    secretName: rustdesk-tls
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt
    # Remote sessions are long-lived WebSockets; the default 60 s idle timeout drops them.
    nginx.ingress.kubernetes.io/proxy-read-timeout: "3600"
    nginx.ingress.kubernetes.io/proxy-send-timeout: "3600"
```

With other routing (an Istio VirtualService, a Gateway API HTTPRoute, ...), route
the host to the `<release>-rustdesk-webclient` Service on port 80 the same way,
keep the `Host` header (the api-server builds its OIDC callback URL from it) and
allow long-lived WebSockets.

## Single instance

hbbs, hbbr and the api-server each run one pod. Postgres holds the durable data,
but each also keeps live state in memory that a second pod would not see:

- hbbs: the open connection of every registered device; a request landing on
  another pod could find the device in Postgres but not reach it.
- hbbr: the two halves of each relayed session must meet in the same pod.
- api-server: OIDC login sessions (a login spans several requests) and a
  write-back address book cache.

Upgrades roll over without a gap (`RollingUpdate`, surge 1). For a few seconds
both pods run: a connection attempt or an OIDC login in flight may need a retry.
Running more replicas is a goal but needs changes in the servers first.

## Network policies and service account

By default the chart adds ingress-only NetworkPolicies: Postgres accepts only hbbs
and the api-server; the api-server only the web client and hbbs; hbbs and hbbr only
the web client. The web client (and the OIDC mock) accept any source, so your
ingress controller or gateway needs no extra rules. Egress is not restricted.
Disable with `networkPolicy.enabled: false`; they need a CNI that enforces
NetworkPolicy (Calico, Cilium, ...).

All pods run under one ServiceAccount with no API token mounted (none of them
talks to the Kubernetes API). Set `serviceAccount.create: false` and
`serviceAccount.name` to use an existing one. There is no PodDisruptionBudget: with
a single replica each, a PDB would block node drains.

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
op = "corp"                  # identifier the client sends back
op_auth_string = "oidc/corp" # must be "oidc/<op>"
issuer = "https://login.example.com/<tenant>/v2.0"  # the IdP's issuer URL
```

- `provider`: `Oauth2` (sends the client secret both as HTTP Basic and in the
  form body), `Dex` (HTTP Basic only) or `Github`. Other names in the code
  (`Azure`, `Okta`, ...) are not implemented and are rejected; use `Oauth2`.
- `scope` must include `openid`: users are identified by the ID token's `sub`.
  `name` (else `preferred_username`) and `email` are only shown, never used to
  match accounts.
- `issuer` is required (except for `Github`): it must equal the `iss` claim of the
  IdP's ID tokens, i.e. the `issuer` in its `/.well-known/openid-configuration`.
  ID tokens with another issuer, another audience than `app_id`, or an expired
  `exp` are rejected.
- Register `https://<your host>/api/oidc/callback` as the redirect URI.
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
api-server's CLI, which works directly on the database:

```bash
# the user must have logged in through OIDC once (that creates the account)
kubectl exec -n rustdesk deploy/rustdesk-apiserver -- /app/rustdesk-api admin promote "Alice Chen"
kubectl exec -n rustdesk deploy/rustdesk-apiserver -- /app/rustdesk-api admin demote "Alice Chen"
```

The user name is the OIDC `name` claim. Upgrading an existing install removes
the old built-in `admin` account (its password was public); the first user you
promote takes over its shared address books.

Starting a connection also requires being logged in: hbbs runs with
`LOGGED_IN_ONLY=Y` by default and checks the client's session with the api-server,
so a client that never logs in cannot connect to anyone. (Devices registering to be
controlled do not need to log in.) Set `hbbs.env.LOGGED_IN_ONLY: "N"` to allow
anonymous connections.

Upstream native clients still show username/password fields; logins through them
always fail. Use "Continue with ..." instead.

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

### Upgrading from 0.2.x

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

## Single-port architecture

For deployments behind a TLS-terminating reverse proxy (e.g., Istio, nginx), all traffic can go through a single domain on port 443:

| Path | Backend | Protocol |
|------|---------|----------|
| `/ws/id` | hbbs:21118 | WebSocket |
| `/ws/relay` | hbbr:21119 | WebSocket |
| `/api/*` | mock 200 | HTTP (for unpatched native clients) |
| `/` | webclient:80 | HTTP |

Enable Istio routing:

```yaml
istio:
  enabled: true
  gateway: istio-system/default-gateway
  hosts:
    - rustdesk.example.com
```

Native clients connect with:
- `custom-rendezvous-server`: `rustdesk.example.com`
- `api-server`: `https://rustdesk.example.com`
