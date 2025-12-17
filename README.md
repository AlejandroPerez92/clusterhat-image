# Manual Node Conversion Kit

This directory bundles the files and script required to convert a fresh Raspberry Pi OS (Debian Bullseye) or Radxa Zero Debian install into a ClusterCTRL Px node (p1–p252) without needing the full Factory image.

## Contents

- `convert-node.sh` – automation of every step in `docs/manual-node-conversion.md` that applies to Bullseye nodes.
- `files/default-clusterctrl` – baseline `/etc/default/clusterctrl` template.
- `files/issue.p` – login banner showing the gadget IPs on `ttyGS0`.
- `files/composite-clusterctrl` – gadget setup helper installed to `/usr/sbin`.
- `files/clusterctrl-composite.service` – systemd unit for the composite gadget.

## Usage

1. Copy this entire folder to the target device (Pi Zero or Radxa Zero) that will become node `pX` (for example with `scp`).
2. If you are on a Radxa Zero, make sure nothing else is using the OTG port. The script automatically disables `amlogic-adbd.service`, but you should unplug/replug the OTG cable after the first run if that service was active.
3. Run the script as root and pass the node number you want:

   ```bash
   sudo ./convert-node.sh 7
   ```

   The script validates the number (1–252) and performs these actions:

   - Seeds `/etc/default/clusterctrl`, sets `TYPE=node` / `ID=X`, and copies the serial-console banner.
   - Updates hostname, `/etc/hosts`, `/etc/issue`, and wires up the usb0 static IP via systemd-networkd.
   - Forces the USB controller into gadget/peripheral mode, removes stale `console=ttyGS0`/`reconfig-clusterctrl` boot arguments, and disables controller-only sysctl toggles.
   - Installs the gadget helper (`/usr/sbin/composite-clusterctrl`) and `clusterctrl-composite.service`, enables the USB serial getty, and disables `clusterctrl-init`. The helper always exposes a single ECM USB Ethernet interface while preserving the standard ClusterCTRL VID/PID and MAC layout, so the controller still renames the link to `ethpiX`.

4. Reboot the device. After the reboot the gadget enumerates as `ClusterCTRL` and exposes the USB serial console plus an ECM USB Ethernet link with the correct static IP (`172.19.181.X`).

Feel free to re-run the script later with a different number—existing settings get updated in-place.
