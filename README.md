# zvps-unikraft-autostart

The [zvps](https://github.com/zv201413/zvps-super) repack for **Unikraft
Cloud** (base project:
[zvps-unikraft](https://github.com/sleeplesshermit/zvps-unikraft)) plus a
**boot-time autostart**: on every start/restart of the instance, an
[argosbx](https://github.com/yonggekkk/argosbx) installer runs 30 seconds
after boot and brings up a VMess-WS node behind a **Cloudflare Tunnel**
(Argo), so the node reconnects itself with zero manual steps.

Built and verified end-to-end on a live instance in 2026-10: boot →
installer completes in ~1 minute → Xray listening on the VMess port →
cloudflared connected (4 HA connections) → the tunnel hostname answers
from the public internet.

## Why it is built this way

Three platform facts drive the design:

1. **The guest rootfs is not persistent.** Files written inside a running
   Unikraft instance are gone after a restart. Anything that must exist
   or run at boot has to be **baked into the image** (or live in
   platform-side instance env — see 3).
2. **The image entrypoint is the boot hook.** The zvps entrypoint runs
   `/home/zv/init_env.sh` (with `sh`) on every boot, before supervisord
   starts. That file is where the autostart lives.
3. **Secrets stay out of the image.** The image contains only the
   *mechanism* (two small scripts). Every value — passwords, the VMess
   UUID, the tunnel token — is supplied per-instance through the
   platform's **environment variables**, so the image is safe to share
   and one image serves any number of instances.

## Layout

| File | Purpose |
| --- | --- |
| `Kraftfile` | Unikraft packaging (erofs rootfs, base-compat runtime) |
| `assemble.sh` | Full rootfs assembly: pull → overlay → hosts fix → autostart overlay |
| `pull_extract.py` | GHCR layer pull + extract with whiteout handling |
| `merge_rootfs.py` | Alternative: merge layers into one tar |
| `overlay/home/zv/init_env.sh` | Boot hook (POSIX sh): schedules the installer at +30 s, never fails the boot |
| `overlay/home/zv/argosbx-run.sh` | Bash runner: feeds the platform env into the argosbx one-liner |
| `env.example` | The 7 instance env vars, with placeholders and where to get each |
| `.gitignore` | Keeps the ~485 MB rootfs and layer blobs out of git |

## Build

```sh
export TMPDIR=$HOME/workspace/tmp-build   # build needs a roomy TMPDIR
sh assemble.sh                             # pull + overlays + hosts fix
unikraft build . --output yourname/zvps:argosbx
unikraft pkg push yourname/zvps:argosbx    # or your registry path
```

`assemble.sh` also bakes the **/etc/hosts fix** (`127.0.0.1 localhost`):
the merged rootfs ships an empty `/etc/hosts`, and without a localhost
entry cloudflared exits at startup because it cannot bind its metrics
listener (it resolves the name through DNS and fails).

## Docker image

The same stack is also packaged as a plain Docker image (the
`Dockerfile` in this repo): `FROM ghcr.io/zv201413/zvps` plus the
autostart overlay. The upstream entrypoint runs `/home/zv/init_env.sh`
on every container start, so the autostart behaves exactly as on
Unikraft — installer at +30 s, all values from the environment:

```sh
docker build -t zvps-unikraft-autostart .
docker run -d --name zvps --env-file <your.env> zvps-unikraft-autostart
```

`<your.env>` holds the same 7 variables as `env.example`. Other
projects can run the image as-is or import it as a base
(`FROM <registry>/zvps-unikraft-autostart`).

Publishing is automated: the GitHub Actions workflow
`.github/workflows/docker.yml` rebuilds and pushes
`ghcr.io/sleeplesshermit/zvps-unikraft-autostart:latest` (plus a
short-SHA tag) to GHCR on every push to `main` that touches the
Dockerfile or the overlay — build-on-push only, no schedule. Note: a
newly published GHCR package starts out **private**; set it to Public
once under the package's Settings → Danger Zone → Change visibility
if you want unauthenticated pulls.

## Deploy

1. Create (or edit) the instance to use the new image.
   **Pin it by digest**, not just by tag:

   ```sh
   unikraft instances edit <instance> --image yourname/zvps@sha256:<digest>
   ```

   An instance keeps the first digest it pulled for a tag; after a
   rebuild, a tag-only reference silently keeps booting the old image.

2. Set the environment variables (see `env.example` for the full list and
   where each value comes from). The autostart needs `VMPT`, `UUID`,
   `AGN`, `AGK`; the base image needs `SSH_USER`, `SSH_PWD`, `TTYD_P1`.

   Two CLI quirks that will otherwise waste your evening:

   - Env edits are **silently ignored while the instance is running** —
     stop it first, edit, then start.
   - `-e` **replaces the whole env table** — pass all keys every time.

3. Start the instance and watch the boot log:

   ```sh
   unikraft instances start <instance>
   unikraft instances logs <instance>   # look for: argosbx autostart scheduled (+30s)
   ```

## Environment variables

| Var | Used by | What it is |
| --- | --- | --- |
| `SSH_USER` | base entrypoint | SSH login user (conventionally `zv`) |
| `SSH_PWD` | base entrypoint | SSH login password — strong and unique |
| `TTYD_P1` | base entrypoint | Password for the ttyd web terminal |
| `VMPT` | argosbx runner | Local VMess-WS port the tunnel forwards to (e.g. `8001`) |
| `UUID` | argosbx runner | VMess UUID — generate your own; clients need the same value |
| `AGN` | argosbx runner | Your tunnel hostname (proxied CNAME to `<tunnel-id>.cfargotunnel.com`) |
| `AGK` | argosbx runner | Cloudflare Tunnel token (Zero Trust → Networks → Tunnels → *Install and run a connector*) |

Full explanations and placeholders: [`env.example`](env.example).
**Never** commit real values, and never bake them into the image.

## How a boot unfolds

1. Entrypoint runs `/home/zv/init_env.sh` (sh) → prints
   `argosbx autostart scheduled (+30s)` and backgrounds
   `( sleep 30; bash /home/zv/argosbx-run.sh )`, output to
   `/home/zv/argosbx-boot.log`.
2. supervisord starts sshd + ttyd as usual.
3. At +30 s, `argosbx-run.sh` runs the argosbx installer with
   `vmpt/uuid/argo=vmpt/agn/agk` taken from the instance env.
4. The installer downloads Xray + cloudflared (into `/agsbx` in this
   environment), starts Xray on `VMPT` and cloudflared with the token.
5. The tunnel hostname now serves the VMess-WS node.

## Verify

- Boot log contains `argosbx autostart scheduled (+30s)` and **no**
  syntax errors.
- Inside the guest: `ss -tlnp` shows Xray on your `VMPT` port;
  `curl 127.0.0.1:20241/metrics | grep ha_connections` shows
  `cloudflared_tunnel_ha_connections 4`.
- From outside: `https://<AGN>/` returns Xray's bare `404` (wrong WS
  path — proof the request reached Xray through the tunnel). A dead
  tunnel returns Cloudflare error 1033 instead.
- Note: Cloudflare's API *connections* list can read empty for a healthy
  token-run tunnel — trust the connector metrics and the public probe.
- Your node links/subscription are in `/agsbx/jhsub.txt` inside the
  guest, and the installer's summary ends `/home/zv/argosbx-boot.log`.

## Gotchas (all learned the hard way)

- **`init_env.sh` must be POSIX sh.** The entrypoint runs it with `sh`
  (dash). A bash-only construct like process substitution `<(...)` is a
  *parse* error that aborts the whole boot (instance restart-loops,
  exit `0x200`). That is why the installer line lives in a separate
  bash-parsed file. Check with `dash -n init_env.sh` before building.
- **Digest pinning** (above): rebuilt tag ≠ running image until the
  instance is re-pointed at the new digest.
- **Env edits need a stopped instance and the full table** (above).
- **Pre-populated `/home/zv`**: because the overlay ships files in the
  user's home, `useradd -m` skips the `/etc/skel` copy at boot and logs a
  warning. Harmless.
- The installer re-runs from scratch on every boot (the fs is ephemeral
  anyway) and takes about a minute; the node is briefly down after each
  restart by design.
