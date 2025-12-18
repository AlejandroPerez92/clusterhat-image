# Ansible K3s Provisioning

This playbook bundle installs k3s on the ClusterCTRL controller and every Px node from an external operator machine. The operator needs SSH access to the controller, while the controller must have SSH access to all nodes.

## Requirements
- Ansible 2.14+
- Python 3 on controller and nodes
- Passwordless SSH from operator -> controller and controller -> nodes (recommended via SSH keys)
- Controller reachable as a bastion (ProxyJump) for nodes

## Layout
- `inventory/hosts.yml` – controller and node definitions, including ProxyJump settings
- `inventory/group_vars/` – shared variables (`all.yml`) and secrets (store sensitive data with Ansible Vault)
- `playbooks/site.yml` – full deployment (controller server + nodes)
- `playbooks/k3s-agent.yml` – rerun only node roles
- `roles/` – reusable role implementations

## Usage
```
cd ansible
ansible-playbook -i inventory/hosts.yml playbooks/site.yml
```

To rerun just the nodes after controller is in place:
```
ansible-playbook -i inventory/hosts.yml playbooks/k3s-agent.yml --tags k3s
```

Store the k3s token in Ansible Vault if you do not want to read it dynamically; otherwise the controller role will read `/var/lib/rancher/k3s/server/node-token` and share it with the node plays.
