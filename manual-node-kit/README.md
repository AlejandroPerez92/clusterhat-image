# Manual Node Conversion Kit

This directory bundles the files and script required to convert a fresh Raspberry Pi OS (Debian Bullseye) install into a ClusterCTRL Px node (p1–p252) without needing the full Factory image.

## Contents

- `convert-node.sh` – automation of every step in `docs/manual-node-conversion.md` that applies to Bullseye nodes.
- `files/default-clusterctrl` – baseline `/etc/default/clusterctrl` template.
- `files/issue.p` – login banner showing the gadget IPs on `ttyGS0`.
- `files/composite-clusterctrl` – gadget setup helper installed to `/usr/sbin`.
- `files/clusterctrl-composite.service` – systemd unit for the composite gadget.

## Usage

1. Copy this entire folder to the Pi that will become node `pX` (for example with `scp`).
2. Run the script as root and pass the node number you want:

   ```bash
   sudo ./convert-node.sh 7
   ```

   The script validates the number (1–252) and performs these actions:

   - Seeds `/etc/default/clusterctrl`, sets `TYPE=node` / `ID=X`, and copies the serial-console banner.
   - Updates hostname, `/etc/hosts`, `/etc/issue`, and the USB gadget static IP entries in `dhcpcd.conf` and (if present) `dhclient.conf`.
   - Forces the USB controller into gadget/peripheral mode, removes stale `console=ttyGS0`/`reconfig-clusterctrl` boot arguments, and disables controller-only sysctl toggles.
   - Installs the gadget helper (`/usr/sbin/composite-clusterctrl`) and `clusterctrl-composite.service`, enables the USB serial getty, and disables `clusterctrl-init`.

3. Reboot the Pi. After the reboot the gadget enumerates as `ClusterCTRL` and exposes the USB serial console plus RNDIS network with the correct static IP (`172.19.181.X`).

Feel free to re-run the script later with a different number—existing settings get updated in-place.
