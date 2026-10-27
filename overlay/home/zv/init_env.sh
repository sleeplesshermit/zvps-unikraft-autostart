#!/bin/sh
# Boot hook - baked into the image, NOT written inside the running guest.
#
# Why baked in: a Unikraft Cloud guest's rootfs is NOT persistent across
# restarts. Anything that must exist at boot has to live in the image.
#
# The zvps entrypoint runs this file (with sh) on every boot, before
# supervisord starts. It only schedules the real work 30 s later, in the
# background, so the system is fully up first - and it must never fail
# the boot, so it always exits 0.
#
# Keep this file POSIX-sh clean: no bashisms, no process substitution.
# The entrypoint runs it with sh (dash), which cannot even parse bash's
# <(...) syntax - a parse error here aborts the whole boot. The actual
# installer line lives in argosbx-run.sh and is parsed by bash only.
#
# All values come from the instance's platform env vars (see env.example):
# VMPT / UUID / AGN / AGK. Nothing secret is baked into the image.
if [ -n "$AGK" ] && [ -n "$UUID" ] && [ -n "$AGN" ]; then
    ( sleep 30; bash /home/zv/argosbx-run.sh ) > /home/zv/argosbx-boot.log 2>&1 &
    echo "argosbx autostart scheduled (+30s)"
fi
exit 0
