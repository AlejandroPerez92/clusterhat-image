# Converting an Existing SD-Boot Install into a Px Node

This guide walks through the exact tweaks the stock reconfiguration script would make when turning an already-initialized Raspberry Pi OS install into a ClusterCTRL node (`p1`–`p252`). Follow the steps in order on the Pi that will become the node. All commands assume `sudo` privileges and an SD-backed root filesystem.

## 1. Pick the Node Number

Choose a free Px slot between 1 and 252. In the commands below replace `$P` with that number (for example `P=3` yields host name `p3` and static IP `172.19.181.3`).

```bash
sudo bash -c 'echo "P=<your-node-number>" >/root/node-id.env'
source /root/node-id.env
```

Keeping the ID in a shell variable avoids typos while editing several files.

## 2. Install the ClusterCTRL Defaults

The node relies on `/etc/default/clusterctrl` for service settings. If the file does not exist, seed it from the packaged template (`files/usr/share/clusterctrl/default-clusterctrl:5-46`). Remove any previous role entries and append the node identity (`files/usr/sbin/reconfig-clusterctrl:60-135`):

```bash
sudo install -m 644 /usr/share/clusterctrl/default-clusterctrl /etc/default/clusterctrl
sudo sed -i '/^TYPE=/d;/^ID=/d' /etc/default/clusterctrl
printf 'TYPE=node\nID=%s\n' "$P" | sudo tee -a /etc/default/clusterctrl
```

## 3. Set Hostname and Friendly Login Banner

Match the hostname and `/etc/hosts` entries to `p$P`, just as the automated script does (`files/usr/sbin/reconfig-clusterctrl:118-123`). Replace `/etc/issue` with the node banner so the gadget’s IP is shown on the USB serial console (`files/usr/share/clusterctrl/issue.p:1-2`):

```bash
echo "p$P" | sudo tee /etc/hostname
sudo sed -i "s#^127.0.1.1.*#127.0.1.1\tp$P#" /etc/hosts
sudo install -m 644 /usr/share/clusterctrl/issue.p /etc/issue
```

## 4. Configure USB Gadget Networking

### Bookworm (netplan/ifupdown)

Install the canned USB NIC stanza (`files/usr/share/clusterctrl/interfaces.bookworm.p:1-3`):

```bash
sudo install -m 644 /usr/share/clusterctrl/interfaces.bookworm.p \
  /etc/network/interfaces.d/clusterctrl
```

### Bullseye and Older (dhcpcd)

Edit `/etc/dhcpcd.conf` and update the fallback profile the same way the script does (`files/usr/sbin/reconfig-clusterctrl:123-126`). This example assumes the stock `static ip_address=172.19.181.253/24 #ClusterCTRL` entry is present:

```bash
sudo sed -i \
  "s#^static ip_address=172\.19\.181\..*/24 #ClusterCTRL#static ip_address=172.19.181.$P/24 #ClusterCTRL#" \
  /etc/dhcpcd.conf
```

### Optional: Bookworm dhclient lease

If `/etc/dhcp/dhclient.conf` exists, also rewrite the static lease the way `reconfig-clusterctrl` does (`files/usr/sbin/reconfig-clusterctrl:126-128`):

```bash
sudo sed -i \
 "s#^  fixed-address 172\.19\.181\..* # ClusterCTRL Px#  fixed-address 172.19.181.$P; # ClusterCTRL Px#" \
 /etc/dhcp/dhclient.conf
```

## 5. Flip the USB Controller Into Device Mode

Nodes must enumerate as USB peripherals. Mirror the overlay edits from the automation (`files/usr/sbin/reconfig-clusterctrl:120-123`). Depending on your image the firmware partition is `/boot/firmware` (Bookworm) or `/boot`.

```bash
BOOT=/boot/firmware
[ -d "$BOOT" ] || BOOT=/boot
sudo sed -i 's/^dtoverlay=dwc2.*$/dtoverlay=dwc2,dr_mode=peripheral/' "$BOOT/config.txt"
sudo sed -i 's/^otg_mode=1 # Controller only$/#otg_mode=1 # Controller only/' "$BOOT/config.txt"
```

## 6. Clean Up Kernel Command Line (Optional but Recommended)

If your image previously used controller reconfiguration, strip any leftover `init=/usr/sbin/reconfig-clusterctrl ...` or `console=ttyGS0` arguments so the Pi boots normally (`files/usr/sbin/reconfig-clusterctrl:49-57`).

```bash
sudo sed -i 's# console=ttyGS0##g;s# init=/usr/sbin/reconfig-clusterctrl [^ ]*##g' "$BOOT/cmdline.txt"
```

## 7. Enable the Right Services

Nodes expose a USB serial console and composite gadget but do not run `clusterctrl-init`. Switch the systemd units to match (`files/usr/sbin/reconfig-clusterctrl:129-135`):

```bash
sudo systemctl disable clusterctrl-init
sudo systemctl enable serial-getty@ttyGS0.service
sudo systemctl enable clusterctrl-composite.service
```

## 8. Reboot and Verify

Reboot the Pi so the gadget service can provision `/sys/kernel/config/usb_gadget` (`files/usr/lib/systemd/system/clusterctrl-composite.service:1-11`). After the reboot:

1. Connect the USB data cable to the ClusterCTRL controller and check that it sees `ethpi$P` and `ttypi$P` (udev rules in `files/etc/udev/rules.d/90-clusterctrl.rules:4-16` rename the gadget automatically).
2. Log in on `ttyGS0`—you should see the IPv4/IPv6 line from `/etc/issue`.
3. Confirm `TYPE=node` and `ID=$P` remain in `/etc/default/clusterctrl`.

Once those checks pass, the converted SD card behaves like a factory-built node image.
