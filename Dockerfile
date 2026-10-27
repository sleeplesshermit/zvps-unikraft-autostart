# zvps + argosbx autostart as a plain Docker image.
#
# The same content the Unikraft pipeline in this repo bakes into an erofs
# rootfs, packaged for Docker so other projects can pull or import it:
#
#     docker build -t zvps-unikraft-autostart .
#     FROM <registry>/zvps-unikraft-autostart   # in a downstream Dockerfile
#
# Base: the upstream zvps image (Ubuntu 22.04, supervisord entrypoint).
# Its entrypoint runs /home/zv/init_env.sh (with sh) on every container
# start, before supervisord - so the argosbx installer fires 30 s after
# every start/restart, exactly as on Unikraft. All values come from
# environment variables at runtime (see env.example); none are baked in.
FROM ghcr.io/zv201413/zvps:latest

# /etc/hosts localhost entry. Docker replaces /etc/hosts at runtime, so
# this is a no-op there - it matters when the image is exported back to
# a rootfs (e.g. Unikraft), where the missing entry makes cloudflared
# exit at startup because it cannot resolve "localhost" for its metrics
# listener.
RUN grep -qE '(^|[[:space:]])localhost([[:space:]]|$)' /etc/hosts \
    || echo '127.0.0.1 localhost' >> /etc/hosts

# Boot hook (POSIX sh; only schedules the installer at +30 s and never
# fails the boot) and its bash runner (feeds VMPT / UUID / AGN / AGK from
# the container env into the argosbx one-liner). See overlay/ and the
# README's "How a boot unfolds".
COPY overlay/home/zv/init_env.sh overlay/home/zv/argosbx-run.sh /home/zv/
RUN chmod 755 /home/zv/init_env.sh /home/zv/argosbx-run.sh
