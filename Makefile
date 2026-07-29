ANSIBLE_PLAYBOOK ?= ansible-playbook
ANSIBLE_GALAXY ?= ansible-galaxy
ANSIBLE_INVENTORY ?= ansible-inventory
ANSIBLE_VAULT ?= ansible-vault
YC ?= yc
JQ ?= jq

INVENTORY ?= inventory.ini
PLAYBOOK ?= playbook.yml
VAULT_FILE := group_vars/webservers/vault.yml
VAULT_ARGS ?= $(if $(wildcard $(VAULT_FILE)),--ask-vault-pass,)
PROJECT6_FOLDER_ID ?=
INVENTORY_SSH_PRIVATE_KEY_FILE ?= ~/.ssh/hexlet-6-ansible

ANSIBLE_RUNTIME_DIR ?= /tmp/hexlet-6-ansible
ANSIBLE_ROLES_DIR ?= $(ANSIBLE_RUNTIME_DIR)/roles
ANSIBLE_COLLECTIONS_DIR ?= $(ANSIBLE_RUNTIME_DIR)/collections
ANSIBLE_ENV = ANSIBLE_HOME=$(ANSIBLE_RUNTIME_DIR)/home \
	ANSIBLE_LOCAL_TEMP=$(ANSIBLE_RUNTIME_DIR)/local \
	ANSIBLE_REMOTE_TEMP=$(ANSIBLE_RUNTIME_DIR)/remote \
	ANSIBLE_ROLES_PATH=$(ANSIBLE_ROLES_DIR) \
	ANSIBLE_COLLECTIONS_PATH=$(ANSIBLE_COLLECTIONS_DIR)

.PHONY: install inventory-refresh prepare deploy monitoring vault-create vault-edit \
	syntax-check check

install:
	mkdir -p $(ANSIBLE_ROLES_DIR) $(ANSIBLE_COLLECTIONS_DIR)
	$(ANSIBLE_ENV) $(ANSIBLE_GALAXY) role install --force \
		--role-file requirements.yml --roles-path $(ANSIBLE_ROLES_DIR)
	$(ANSIBLE_ENV) $(ANSIBLE_GALAXY) collection install --force \
		--requirements-file requirements.yml \
		--collections-path $(ANSIBLE_COLLECTIONS_DIR)

inventory-refresh:
	@PROJECT6_FOLDER_ID="$(PROJECT6_FOLDER_ID)" \
		INVENTORY="$(INVENTORY)" \
		INVENTORY_SSH_PRIVATE_KEY_FILE="$(INVENTORY_SSH_PRIVATE_KEY_FILE)" \
		YC="$(YC)" \
		JQ="$(JQ)" \
		ANSIBLE_INVENTORY="$(ANSIBLE_INVENTORY)" \
		$(ANSIBLE_ENV) ./scripts/inventory-refresh.sh $(VAULT_ARGS)

prepare:
	$(ANSIBLE_ENV) $(ANSIBLE_PLAYBOOK) --inventory $(INVENTORY) \
		$(VAULT_ARGS) $(PLAYBOOK) --tags prepare

deploy:
	$(ANSIBLE_ENV) $(ANSIBLE_PLAYBOOK) --inventory $(INVENTORY) \
		$(VAULT_ARGS) $(PLAYBOOK) --tags deploy

monitoring:
	$(ANSIBLE_ENV) $(ANSIBLE_PLAYBOOK) --inventory $(INVENTORY) \
		$(VAULT_ARGS) $(PLAYBOOK) --tags monitoring

vault-create:
	$(ANSIBLE_ENV) $(ANSIBLE_VAULT) create --ask-vault-pass \
		group_vars/webservers/vault.yml

vault-edit:
	$(ANSIBLE_ENV) $(ANSIBLE_VAULT) edit --ask-vault-pass \
		group_vars/webservers/vault.yml

syntax-check:
	$(ANSIBLE_ENV) $(ANSIBLE_PLAYBOOK) --inventory $(INVENTORY) \
		$(VAULT_ARGS) --syntax-check $(PLAYBOOK)

check: syntax-check
	$(ANSIBLE_ENV) $(ANSIBLE_INVENTORY) --inventory $(INVENTORY) \
		$(VAULT_ARGS) --graph
	$(ANSIBLE_ENV) $(ANSIBLE_PLAYBOOK) --inventory $(INVENTORY) \
		$(VAULT_ARGS) --check --list-tasks $(PLAYBOOK)
	$(ANSIBLE_ENV) $(ANSIBLE_PLAYBOOK) --inventory $(INVENTORY) \
		$(VAULT_ARGS) --list-tags $(PLAYBOOK)
