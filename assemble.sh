#!/bin/sh
# Assemble the Unikraft rootfs for zvps + the argosbx autostart overlay.
#
# Pipeline:
#   1. Pull the published ghcr.io/zv201413/zvps image layers and extract them
#      into ./rootfs, honouring OCI whiteouts (pull_extract.py).
#   2. Overlay the zvps-super source files (entrypoint.sh & friends) on top.
#   3. Fix /etc/hosts (see below).
#   4. Overlay the autostart hook (overlay/home/zv/) into the rootfs.
# Afterwards:  unikraft build  /  unikraft pkg push  (see Kraftfile)
#
# NOTE: small /tmp filesystems will fail the build; point TMPDIR at a roomy
# directory first, e.g.  export TMPDIR=$HOME/workspace/tmp-build
set -eu
cd "$(dirname "$0")"

python3 pull_extract.py

# Overlay the upstream source (entrypoint.sh, supervisord.conf, fragments/…)
if [ ! -d zvps-super ]; then
  git clone --depth 1 https://github.com/zv201413/zvps-super.git
fi
cp -a zvps-super/. rootfs/
rm -rf rootfs/.git rootfs/.github

# --- /etc/hosts fix -------------------------------------------------------
# The merged rootfs ships an EMPTY /etc/hosts: Docker injects one at runtime,
# Unikraft's base-compat runtime does not. With no "localhost" entry the name
# goes to DNS and fails, and cloudflared exits because it cannot bind its
# metrics listener on localhost. Bake the entry into the rootfs.
touch rootfs/etc/hosts
grep -qE '(^|[[:space:]])localhost([[:space:]]|$)' rootfs/etc/hosts ||
  echo '127.0.0.1 localhost' >> rootfs/etc/hosts

# --- autostart overlay ------------------------------------------------------
# The entrypoint runs /home/zv/init_env.sh (with sh) on every boot, before
# supervisord. Baking the hook into the image is the ONLY way it survives
# restarts: the guest rootfs is not persistent. Side effect: because
# /home/zv is pre-populated, useradd -m skips copying /etc/skel at boot and
# logs a harmless warning about it.
cp -a overlay/. rootfs/
chmod 755 rootfs/home/zv/init_env.sh rootfs/home/zv/argosbx-run.sh

echo "rootfs ready: $(du -sh rootfs | cut -f1), /etc/hosts:"
cat rootfs/etc/hosts
echo "autostart hook:"
ls -l rootfs/home/zv/init_env.sh rootfs/home/zv/argosbx-run.sh
