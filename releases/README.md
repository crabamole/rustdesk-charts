# Chart releases

One file per chart release: `<version>.md`, named after `version` in `charts/Chart.yaml`. CI copies it,
without its `#` title, into the GitHub Release `<version>` and fails when it is missing.

The chart deploys rustdesk-server, rustdesk-api and the web client, so their changes are listed here.
To read a range of releases: `ls | sort -V`.

Template:

```markdown
# Helm chart <version>

Images: rustdesk-server <v>, rustdesk-api <v>, web client <v>. Native clients: <v>.

## Changes

- Per component, what changed since the previous chart release.

## Upgrade steps

- What to do before or after `helm upgrade`, or "None".
```
