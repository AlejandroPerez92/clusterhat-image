# Node Image Provisioning Flow

The project creates *node* (Px) images by cloning the controller build, tagging each copy with a first‑boot reconfiguration job, and letting the Pi Zero finish the personalization the first time it powers on. This document follows that journey end‑to‑end so you can see every moving part that touches the node role.

## 1. Build-Time Steps

1. **Choose how many nodes to emit per image flavour.** The `MAXPLITE`, `MAXPSTD`, and `MAXPFULL` knobs in `build/config.sh:36-39` decide how many Px images are generated after the base controller image is prepared.
2. **Seed fallback networking for unconfigured nodes.** Before any roles are carved out, `build/create.sh:322-375` writes a `dhclient.conf`/`dhcpcd.conf` profile that assigns every USB gadget (`usb0`) a temporary `172.19.181.253` address so brand-new nodes can still talk to the controller long enough to be renumbered.
3. **Copy the controller image for each Px.** After the bridged controller image (`-CBRIDGE.img`) is ready, the loop in `build/create.sh:630-650` copies it to `*-pX.img` and rewrites `/boot*/cmdline.txt` so PID `pX` boots with `init=/usr/sbin/reconfig-clusterctrl pX`. Nothing else is changed at image-build time—the per-node customisation is deferred to the next step.

## 2. First-Boot Reconfiguration (`reconfig-clusterctrl`)

When a Px image boots, `init=/usr/sbin/reconfig-clusterctrl pX` makes the reconfiguration script run as PID 1.

1. **Safety and validation.** The script mounts `/boot`, remounts `/` read/write, ensures the argument matches `p1`–`p252`, and cleans any previous `init=` or `console=ttyGS0` flags in `cmdline.txt` so the system can proceed with a normal boot afterwards (`files/usr/sbin/reconfig-clusterctrl:38-57`).
2. **Ensure `/etc/default/clusterctrl` exists.** If the file is missing it copies the stock template and notes that the filesystem still needs to expand on the next boot (`files/usr/sbin/reconfig-clusterctrl:60-69` & `files/usr/share/clusterctrl/default-clusterctrl:5-46`).
3. **Apply node-specific identity.** For argument `pX`, the script:
   - Removes any controller interface snippets and, on Bookworm, drops in the lightweight `usb0` DHCP stanza from `interfaces.bookworm.p` (`files/usr/sbin/reconfig-clusterctrl:113-118`, `files/usr/share/clusterctrl/interfaces.bookworm.p:1-3`).
   - Copies the node login banner that shows the USB gadget IPs (`files/usr/share/clusterctrl/issue.p:1-2`).
   - Sets `/etc/hostname` and `/etc/hosts` to `pX` and rewrites `dtoverlay=dwc2,dr_mode=peripheral` plus unsets `otg_mode` so the Zero behaves as a USB *device* (`files/usr/sbin/reconfig-clusterctrl:118-123`).
4. **Lock down network addressing.** The fallback IP laid down at build time is rewritten to the node-specific `172.19.181.X` entry in both `dhcpcd.conf` and the Bookworm `dhclient.conf` lease so the interface works even without DHCP (`files/usr/sbin/reconfig-clusterctrl:124-128`).
5. **Toggle services and record the role.** Nodes enable an interactive USB serial console (`serial-getty@ttyGS0`), disable the controller-only `clusterctrl-init`, and flip `/etc/default/clusterctrl` to `TYPE=node` / `ID=X` before enabling the gadget service (`files/usr/sbin/reconfig-clusterctrl:129-135`).
6. **Restore normal boot.** If this was the first boot, the script appends Raspberry Pi OS’ `firstboot`/`init_resize` helper back into `cmdline.txt`, remounts filesystems read-only, and hard reboots so the system comes back as a fully configured node (`files/usr/sbin/reconfig-clusterctrl:144-156`).

## 3. Runtime Behaviour on a Node

1. **USB composite gadget.** The oneshot service in `files/usr/lib/systemd/system/clusterctrl-composite.service:1-11` starts `/usr/sbin/composite-clusterctrl` after the node comes up. That script:
   - Reads `TYPE` and `ID` from `/etc/default/clusterctrl`.
   - Builds a configfs gadget with one RNDIS NIC (`usb0`) and one ACM serial channel, stamping deterministic MAC addresses from the node ID so the controller can predictably rename interfaces (`files/usr/sbin/composite-clusterctrl:13-70`).
   - Presents vendor ID `0x3171`/product `0x0020`, matching the controller-side udev rules.
2. **Console access.** Because `serial-getty@ttyGS0` is enabled during reconfig, the ACM function exposes a login shell over the USB cable, which mirrors the IPv4/IPv6 gadget status shown in `/etc/issue`.
3. **Network targeting and host view.** On the controller, `files/etc/udev/rules.d/90-clusterctrl.rules:4-21` renames the gadget NIC to `ethpi<ID>` (SD boot) or `ethupi<ID>` (usbboot) and symlinks the serial port to `ttypi<ID>`, so each node’s MAC derived from `00:22:82:ff:ff:ID` maps back to the Px number automatically.

## 4. USB-Boot Nodes (rpiboot/NFS Root)

If you build the optional usbboot tarball, each exported root lives under `/var/lib/clusterctrl/nfs/pX`. Running `reconfig-usbboot X` post-build updates the hostname, `/etc/hosts`, the `nfsroot` path, and the static gadget IP for that exported root before regenerating rpiboot symlinks (`files/usr/share/clusterctrl/reconfig-usbboot:3-23`). The same IP plan (`172.19.180.X` for the NFS interface and `172.19.181.X` for the USB gadget) keeps usbboot nodes aligned with their SD-boot siblings.

## 5. Putting It Together

End-to-end, the node workflow is:

1. Build copies of the controller image tagged with `init=/usr/sbin/reconfig-clusterctrl pX`.
2. First boot runs `reconfig-clusterctrl`, which brands the system as node `pX`, sets static gadget addressing, flips services, and reboots.
3. On every subsequent boot the gadget stack (serial + RNDIS) comes up automatically, the controller renames the link to `ethpiX`, and the node behaves like a USB peripheral with a known IP + serial identity.

Understanding these stages lets you tweak any piece—e.g., change the USB gadget descriptor, alter fallback IP space, or build more than the four default nodes—without guessing how the build system wires the roles together.
