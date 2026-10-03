# Upgrading

Steps to take before or after `helm upgrade`, newest version first. Versions not
listed need nothing beyond the upgrade itself.

## 0.6.3

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
  api-server's migration also fixes file-transfer audit records that had the
  remote and local device swapped; existing rows are not corrected.

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
