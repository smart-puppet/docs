#!/usr/bin/env bash
# Publish puppet.local via Avahi for as long as this process runs.
# Used by puppet-mdns.service (survives logout; re-publishes if the LAN IP changes).
set -euo pipefail

NAME="${PUPPET_MDNS_NAME:-puppet.local}"

lan_ip() {
  ip -4 route get 1.1.1.1 2>/dev/null \
    | awk '{for (i = 1; i <= NF; i++) if ($i == "src") { print $(i + 1); exit }}'
}

child=""
cleanup() {
  if [[ -n "${child}" ]] && kill -0 "${child}" 2>/dev/null; then
    kill "${child}" 2>/dev/null || true
    wait "${child}" 2>/dev/null || true
  fi
  child=""
}
trap cleanup EXIT INT TERM

prev=""
while true; do
  ip="$(lan_ip || true)"
  if [[ -z "${ip}" ]]; then
    sleep 2
    continue
  fi
  if [[ "${ip}" != "${prev}" ]] || [[ -z "${child}" ]] || ! kill -0 "${child}" 2>/dev/null; then
    cleanup
    echo "Publishing ${NAME} -> ${ip}"
    avahi-publish -a -R "${NAME}" "${ip}" &
    child=$!
    prev="${ip}"
  fi
  sleep 5
done
