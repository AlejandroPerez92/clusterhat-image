# Ansible Project Plan for K3s Node Provisioning

## Goals
- Automate post-conversion configuration of every Px node (Pi/Radxa) using Ansible.
- Install and configure k3s in agent mode on each node, pointing at a controller-provided server token/URL.
- Keep playbooks idempotent so reruns correct drift without reimaging nodes.

## Repository Layout
```
ansible/
├── inventory/
│   ├── hosts.yml           # dynamic/static inventory generated from Px list
│   └── group_vars/
│       ├── all.yml         # cluster-wide defaults (controller IP, k3s version, etc.)
│       └── nodes.yml       # vars specific to Px nodes
├── roles/
│   ├── prereqs             # enable ssh, ensure packages, set hostname facts
│   ├── k3s-agent           # install/upgrade/start k3s agent
│   └── postinstall         # optional tuning (sysctl, services, monitoring)
├── playbooks/
│   ├── site.yml            # orchestrates all roles
│   └── k3s-agent.yml       # focused play to (re)install k3s
└── README.md               # usage docs + variable descriptions
```

## Implementation Steps
1. **Bootstrap Ansible skeleton**
   - Create `ansible/` directory with inventory, playbooks, roles folders.
   - Drop a `requirements.txt` (if using collections) and `README.md` explaining prerequisites (Python on controller, SSH keys).

2. **Inventory + Variables**
   - Maintain `inventory/hosts.yml` describing two hops:
     - `controller` group: the main cluster controller reachable from the operator machine.
     - `nodes` group: Px hosts accessible only via SSH proxy through the controller (use `ansible_ssh_common_args: '-o ProxyJump=controller_user@controller_host'` or bastion plugin).
   - Add `group_vars/all.yml` for shared settings: `k3s_version`, `k3s_server_url`, `k3s_token`, controller bridge IP, DNS, NTP.
   - Optionally script generation of hosts file from known Px range.

3. **Role: controller-k3s-server**
   - Runs on the controller host to install/configure `k3s` in server mode.
   - Tasks: install k3s binary/service, ensure `/etc/rancher/k3s/config.yaml` pins the desired ports/node-taints, and generate/record the cluster token in a secure location (`/var/lib/rancher/k3s/server/node-token` copied to Ansible host vars or vault).
   - Expose Kubernetes API address (`https://controller-ip:6443`) to downstream roles.

4. **Role: prereqs (nodes)**
   - Tasks: ensure locale/timezone, install base packages (curl, iptables, nfs-common), configure `/etc/hosts` entries, sync `/etc/default/clusterctrl` facts.
   - Verify USB gadget interface is up and has correct IP (facts for debugging).

5. **Role: k3s-agent**
   - Download k3s install script (or use packaged binary) pinned to `k3s_version`.
   - Ensure `/etc/rancher/k3s/config.yaml` contains server URL, token, node-labels.
   - Manage systemd unit (`k3s-agent.service`), enable + start.
   - Handle upgrades idempotently by checking installed version vs desired.

6. **Role: postinstall (optional)**
   - Tune sysctls for k3s (e.g., `br_netfilter`, `vm.overcommit_memory`).
   - Enable log rotation, install monitoring agents if needed.
   - Register node with controller (write status file, update inventory tags).

7. **Playbook Wiring**
   - `site.yml`: 
     1. Run `controller-k3s-server` on the `controller` group to install k3s server and gather the token (register fact / write to `hostvars`).
     2. Run `prereqs`, `k3s-agent`, `postinstall` on the `nodes` group, leveraging the token and API URL collected from the controller. Always connect through the controller jump host, and `delegate_to: controller` for tasks that must read files like `/var/lib/rancher/k3s/server/node-token`.
   - Provide tags (`pre`, `k3s`, `post`) so operators can run subsets.

7. **Testing & Validation**
   - Use `ansible-playbook --check` on a staging node.
   - Document rollback: how to uninstall k3s agent, clean `/var/lib/rancher/k3s`.
   - Add CI linting (ansible-lint) for playbooks.

8. **Documentation**
   - Update root README or add `ansible/README.md` covering:
     - prerequisites (SSH keys, Python, Ansible version)
     - how to set inventory and secrets (vault for k3s token)
     - common commands (`ansible-playbook -i inventory/hosts.yml playbooks/site.yml`)
