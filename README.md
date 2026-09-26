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

The chart requires a Kubernetes secret containing the hbbs keypair.

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
  # Public relay address advertised to clients (must be externally resolvable).
  # Required for single-port deployments behind a reverse proxy.
  relayAddress: "rustdesk.example.com:443"

webclient:
  env:
    RUSTDESK_KEY: "your-public-key-here"
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

Upstream native clients still show username/password fields; logins through them
always fail. Use "Continue with ..." instead.

## Database

hbbs and the api-server run as separate pods sharing one PostgreSQL database. The
api-server creates and migrates the schema on startup; hbbs waits for it to be
ready before serving.

**Default (evaluation, small installs):** bundled single-instance PostgreSQL
(`postgresql.enabled=true`), no HA or backups.

**Production:** disable the bundled database and point at your own:

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

The api-server always runs a single replica, because OIDC sessions are kept in
memory. `MAX_DATABASE_CONNECTIONS` defaults to `10` for hbbs and `20` for the
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
