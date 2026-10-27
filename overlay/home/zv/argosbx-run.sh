#!/bin/bash
# Runs the argosbx one-click installer with this instance's platform env.
# Invoked by init_env.sh 30 s after boot; parsed by bash only (the line
# below uses process substitution, which is why it does NOT live in the
# sh-run init_env.sh).
#
# Variable mapping (argosbx's own names on the left, platform env on the
# right): vmpt = local VMess-WS port, uuid = VMess UUID, argo = "vmpt"
# (route the tunnel to the VMess port), agn = tunnel hostname,
# agk = Cloudflare Tunnel token. See env.example for where to get each.
vmpt="${VMPT:-8001}" uuid="$UUID" argo="vmpt" agn="$AGN" agk="$AGK" \
    bash <(curl -Ls https://raw.githubusercontent.com/yonggekkk/argosbx/main/argosbx.sh)
