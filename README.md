# rustdesk-charts

Helm charts for deploying RustDesk OSS server components, using forked images that enable web client and WebSocket support.

## Components

| Component | Container Image | Source Repo | Description |
|-----------|----------------|-------------|-------------|
| hbbs | `ghcr.io/rophy/rustdesk-server` | [rophy/rustdesk-server](https://github.com/rophy/rustdesk-server) | Rendezvous server |
| hbbr | `ghcr.io/rophy/rustdesk-server` | [rophy/rustdesk-server](https://github.com/rophy/rustdesk-server) | Relay server |
| web-client | `ghcr.io/rophy/rustdesk/web-client` | [rophy/rustdesk](https://github.com/rophy/rustdesk) | Browser-based remote desktop client |

## Why forked images?

The RustDesk web client and WebSocket-based peer registration were [removed from the upstream OSS builds](https://github.com/rustdesk/rustdesk) and are now only available in RustDesk Server Pro. The forked repos restore these features for the OSS server:

- [rophy/rustdesk](https://github.com/rophy/rustdesk) — restores the web client with OSS server compatibility patches
- [rophy/rustdesk-server](https://github.com/rophy/rustdesk-server) — enables WebSocket peer registration for web client connectivity

## Prerequisites

### Generate keypair

The chart requires a Kubernetes secret containing the hbbs keypair.

```bash
# Generate keypair
output=$(docker run --rm --entrypoint /usr/bin/rustdesk-utils \
  ghcr.io/rophy/rustdesk-server:1.1.17-20260824-1 genkeypair)
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
  host: rustdesk.example.com
```

Native clients connect with:
- `custom-rendezvous-server`: `rustdesk.example.com`
- `api-server`: `https://rustdesk.example.com`
