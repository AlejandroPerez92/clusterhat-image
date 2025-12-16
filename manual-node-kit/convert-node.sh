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

configure_dhcpcd() {
  local ip_last_octet=$1
  local file=/etc/dhcpcd.conf
  if [[ ! -f $file ]]; then
    log "Skipping dhcpcd.conf (not present)"
    return
  fi
  if ! grep -q 'clusterctrl_fallback_usb0' "$file"; then
    cat <<'BLOCK' >> "$file"

# --- ClusterCTRL Px config (managed by convert-node.sh) ---
profile clusterctrl_fallback_usb0
static ip_address=172.19.181.253/24 #ClusterCTRL
static routers=172.19.181.254
static domain_name_servers=8.8.8.8 208.67.222.222

interface usb0
fallback clusterctrl_fallback_usb0
# --- End ClusterCTRL Px config ---
BLOCK
  fi
  sed -i "s#^static ip_address=172\\.19\\.181\\..*/24 #ClusterCTRL#static ip_address=172.19.181.${ip_last_octet}/24 #ClusterCTRL#" "$file"
}

configure_dhclient() {
  local ip_last_octet=$1
  local file=/etc/dhcp/dhclient.conf
  [[ -f $file ]] || return
  if ! grep -q 'ClusterCTRL Px' "$file"; then
    cat <<'BLOCK' >> "$file"

# START ClusterCTRL Px config (managed by convert-node.sh)
lease { # Px
  interface "usb0";
  fixed-address 172.19.181.253; # ClusterCTRL Px
  option subnet-mask 255.255.255.0;
  option routers 172.19.181.254;
  option domain-name-servers 8.8.8.8;
  renew never;
  rebind never;
  expire never;
}
# END ClusterCTRL Px config
BLOCK
  fi
  sed -i "s#^  fixed-address 172\\.19\\.181\\..* # ClusterCTRL Px#  fixed-address 172.19.181.${ip_last_octet}; # ClusterCTRL Px#" "$file"
}

update_config_txt() {
  local config_file=$1
  if grep -q '^dtoverlay=dwc2' "$config_file"; then
    sed -i 's/^dtoverlay=dwc2.*$/dtoverlay=dwc2,dr_mode=peripheral/' "$config_file"
  else
    echo 'dtoverlay=dwc2,dr_mode=peripheral' >> "$config_file"
  fi
  if grep -q '^otg_mode=1' "$config_file"; then
    sed -i 's/^otg_mode=1.*$/#&/' "$config_file"
  fi
}

clean_cmdline() {
  local cmdline_file=$1
  sed -i 's# console=ttyGS0##g' "$cmdline_file"
  sed -i 's# init=/usr/sbin/reconfig-clusterctrl [^ ]*##g' "$cmdline_file"
  sed -i 's# init=/sbin/reconfig-clusterctrl [^ ]*##g' "$cmdline_file"
}

install_services() {
  local assets_dir=$1
  ensure_file_from_assets "$assets_dir/composite-clusterctrl" /usr/sbin/composite-clusterctrl 755
  ensure_file_from_assets "$assets_dir/clusterctrl-composite.service" /etc/systemd/system/clusterctrl-composite.service 644
  systemctl daemon-reload
  systemctl enable --now clusterctrl-composite.service
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
  local boot_dir=/boot/firmware
  [[ -d $boot_dir ]] || boot_dir=/boot
  local config_txt="$boot_dir/config.txt"
  local cmdline_txt="$boot_dir/cmdline.txt"

  log "Configuring /etc/default/clusterctrl"
  ensure_file_from_assets "$assets_dir/default-clusterctrl" /etc/default/clusterctrl 644
  sed -i '/^TYPE=/d;/^ID=/d' /etc/default/clusterctrl
  printf 'TYPE=node\nID=%s\n' "$node_number" >> /etc/default/clusterctrl

  log "Setting hostname to $hostname"
  echo "$hostname" > /etc/hostname
  update_hosts "$hostname"

  log "Updating /etc/issue"
  ensure_file_from_assets "$assets_dir/issue.p" /etc/issue 644

  log "Configuring USB gadget network fallback"
  configure_dhcpcd "$node_number"
  configure_dhclient "$node_number"

  if [[ -f $config_txt ]]; then
    log "Updating $config_txt"
    update_config_txt "$config_txt"
  else
    log "Warning: $config_txt not found"
  fi

  if [[ -f $cmdline_txt ]]; then
    log "Cleaning kernel cmdline"
    clean_cmdline "$cmdline_txt"
  else
    log "Warning: $cmdline_txt not found"
  fi

  log "Installing composite gadget service"
  install_services "$assets_dir"

  log "Enabling USB serial console"
  systemctl enable --now serial-getty@ttyGS0.service
  systemctl disable --now clusterctrl-init.service >/dev/null 2>&1 || true

  log "Disabling ClusterCTRL kernel forwarding toggle"
  if [[ -f /etc/sysctl.conf ]]; then
    sed -i 's/^net.ipv4.ip_forward=1 # ClusterCTRL/#net.ipv4.ip_forward=1 # ClusterCTRL/' /etc/sysctl.conf || true
  fi

  log "Conversion complete. Reboot to apply gadget configuration."
}

main "$@"
