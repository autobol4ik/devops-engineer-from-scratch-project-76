### Hexlet tests and linter status:
[![Actions Status](https://github.com/autobol4ik/devops-engineer-from-scratch-project-76/actions/workflows/hexlet-check.yml/badge.svg)](https://github.com/autobol4ik/devops-engineer-from-scratch-project-76/actions)

[Redmine](https://hexlet-6-redmine.site)

## System requirements

- Python 3
- Ansible Core 2.21.2
- GNU Make
- SSH access to both servers from `inventory.ini`
- Ansible Vault password
- Yandex Cloud CLI and `jq` for inventory refresh

## Install dependencies

```sh
make install
```

## Prepare servers

Enter the Ansible Vault password when a Make target prompts for it. To update
the encrypted variables, run:

```sh
make vault-edit
```

The Vault defines `vault_redmine_db_password`,
`vault_redmine_secret_key_base`, and `vault_datadog_api_key`.

Refresh the tracked inventory after the virtual machine public addresses change:

```sh
export PROJECT6_FOLDER_ID=your-folder-id
make inventory-refresh
```

Install Docker and the required Python packages on both servers:

```sh
make prepare
```

## Deploy Redmine

```sh
make deploy
```

## Configure monitoring

```sh
make monitoring
```

## Run checks

```sh
make check
```
