#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Usage: sudo ./convert-node.sh <node-number>" >&2
  exit 1
}

log() {
  echo "[convert-node] $*"
}

require_root() {
  if [[ $(id -u) -ne 0 ]]; then
    echo "This script must be run as root." >&2
    exit 1
  fi
}

disable_service_if_present() {
  local svc=$1
  if systemctl list-unit-files "$svc" >/dev/null 2>&1; then
    systemctl disable --now "$svc" >/dev/null 2>&1 || true
  fi
}

validate_node_number() {
  local value=$1
  if [[ ! $value =~ ^[0-9]+$ ]] || (( value < 1 || value > 252 )); then
    echo "Node number must be an integer between 1 and 252." >&2
    exit 1
  fi
}

ensure_file_from_assets() {
  local source=$1
  local dest=$2
  local mode=$3
  install -Dm"$mode" "$source" "$dest"
}

update_hosts() {
  local hostname=$1
  if grep -q '^127.0.1.1' /etc/hosts; then
    sed -i "s#^127.0.1.1.*#127.0.1.1\t${hostname}#" /etc/hosts
  else
    echo -e "127.0.1.1\t${hostname}" >> /etc/hosts
  fi
}

configure_networkd() {
  local ip_last_octet=$1
  local network_dir=/etc/systemd/network
  mkdir -p "$network_dir"
cat <<EOF > "$network_dir/99-clusterctrl-usb0.network"
[Match]
Name=usb0

[Network]
Address=172.19.181.${ip_last_octet}/24
Gateway=172.19.181.254
DNS=8.8.8.8
IPv6AcceptRA=no
LinkLocalAddressing=no

[Link]
ConfigureWithoutCarrier=yes
EOF
systemctl enable systemd-networkd.service >/dev/null 2>&1 || true
return 0
}

install_services() {
  local assets_dir=$1
  ensure_file_from_assets "$assets_dir/composite-clusterctrl" /usr/sbin/composite-clusterctrl 755
  ensure_file_from_assets "$assets_dir/clusterctrl-composite.service" /etc/systemd/system/clusterctrl-composite.service 644
  systemctl daemon-reload
  systemctl enable clusterctrl-composite.service
}

main() {
  require_root
  [[ $# -eq 1 ]] || usage
  local node_number=$1
  validate_node_number "$node_number"
  local script_dir
  script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
  local assets_dir="$script_dir/files"
  if [[ ! -d $assets_dir ]]; then
    echo "Assets directory not found: $assets_dir" >&2
    exit 1
  fi
  local hostname="p${node_number}"

  log "Configuring /etc/default/clusterctrl"
  ensure_file_from_assets "$assets_dir/default-clusterctrl" /etc/default/clusterctrl 644
  sed -i '/^TYPE=/d;/^ID=/d' /etc/default/clusterctrl
  printf 'TYPE=node\nID=%s\n' "$node_number" >> /etc/default/clusterctrl

  log "Setting hostname to $hostname"
  echo "$hostname" > /etc/hostname
  update_hosts "$hostname"

  log "Updating /etc/issue"
  ensure_file_from_assets "$assets_dir/issue.p" /etc/issue 644

  log "Configuring USB gadget network via systemd-networkd"
  if ! configure_networkd "$node_number"; then
    log "WARNING: usb0 static IP not configured automatically; please configure manually."
  fi

  log "Ensuring usb0 default route via controller"
  ip route replace default via 172.19.181.254 dev usb0 || true

  log "Pointing /etc/resolv.conf to systemd-resolved stub"
  if [ -f /run/systemd/resolve/stub-resolv.conf ]; then
    ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf
  fi

  log "Installing composite gadget service"
  disable_service_if_present amlogic-adbd.service
  install_services "$assets_dir"

  log "Enabling USB serial console"
  systemctl enable serial-getty@ttyGS0.service

  log "Disabling ClusterCTRL kernel forwarding toggle"
  if [[ -f /etc/sysctl.conf ]]; then
    sed -i 's/^net.ipv4.ip_forward=1 # ClusterCTRL/#net.ipv4.ip_forward=1 # ClusterCTRL/' /etc/sysctl.conf || true
  fi

  log "Conversion complete. Reboot to apply gadget configuration."
}

main "$@"
