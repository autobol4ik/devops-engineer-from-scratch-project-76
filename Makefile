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
	@set -eu; \
		folder_id="$(PROJECT6_FOLDER_ID)"; \
		if [ -z "$$folder_id" ]; then \
			echo "Set PROJECT6_FOLDER_ID to the exact Yandex Cloud folder ID" >&2; \
			exit 1; \
		fi; \
		command -v "$(YC)" >/dev/null 2>&1 || \
			{ echo "Yandex Cloud CLI is unavailable: $(YC)" >&2; exit 1; }; \
		command -v "$(JQ)" >/dev/null 2>&1 || \
			{ echo "jq is unavailable: $(JQ)" >&2; exit 1; }; \
		instances_json="$$("$(YC)" compute instance list \
			--folder-id "$$folder_id" --format json)"; \
		printf '%s\n' "$$instances_json" | "$(JQ)" -e \
			'type == "array"' >/dev/null || \
			{ echo "Yandex Cloud CLI returned an invalid instance list" >&2; exit 1; }; \
		instance_ip() { \
			host_name="$$1"; \
			exact_matches="$$(printf '%s\n' "$$instances_json" | \
				"$(JQ)" -c --arg name "$$host_name" \
				'[.[] | select(.name == $$name)]')"; \
			match_count="$$(printf '%s\n' "$$exact_matches" | \
				"$(JQ)" -r 'length')"; \
			if [ "$$match_count" -ne 1 ]; then \
				echo "Expected exactly one RUNNING instance named $$host_name, found $$match_count" >&2; \
				return 1; \
			fi; \
			status="$$(printf '%s\n' "$$exact_matches" | \
				"$(JQ)" -r '.[0].status // empty')"; \
			if [ "$$status" != "RUNNING" ]; then \
				echo "Instance $$host_name is not RUNNING: $${status:-unknown}" >&2; \
				return 1; \
			fi; \
			address="$$(printf '%s\n' "$$exact_matches" | "$(JQ)" -r \
				'.[0].network_interfaces[0].primary_v4_address.one_to_one_nat.address // empty')"; \
			if ! "$(JQ)" -en --arg address "$$address" \
				'($$address | split(".")) as $$octets | ($$octets | length == 4) and all($$octets[]; test("^[0-9]{1,3}$$") and ((tonumber >= 0) and (tonumber <= 255)))' \
				>/dev/null; then \
				echo "Instance $$host_name has no valid public IPv4" >&2; \
				return 1; \
			fi; \
			printf '%s\n' "$$address"; \
		}; \
		web_1_ip="$$(instance_ip hexlet-6-web-1)"; \
		web_2_ip="$$(instance_ip hexlet-6-web-2)"; \
		inventory_dir="$$(dirname -- "$(INVENTORY)")"; \
		inventory_name="$$(basename -- "$(INVENTORY)")"; \
		tmp_inventory="$$(mktemp "$$inventory_dir/.$$inventory_name.XXXXXX")"; \
		trap 'rm -f -- "$$tmp_inventory"' 0 1 2 15; \
		{ \
			printf '[webservers]\n'; \
			printf '%s ansible_host=%s ansible_user=ubuntu ansible_ssh_private_key_file=%s\n' \
				hexlet-6-web-1 "$$web_1_ip" "$(INVENTORY_SSH_PRIVATE_KEY_FILE)"; \
			printf '%s ansible_host=%s ansible_user=ubuntu ansible_ssh_private_key_file=%s\n' \
				hexlet-6-web-2 "$$web_2_ip" "$(INVENTORY_SSH_PRIVATE_KEY_FILE)"; \
		} >"$$tmp_inventory"; \
		chmod 0600 "$$tmp_inventory"; \
		inventory_graph="$$( \
			$(ANSIBLE_ENV) $(ANSIBLE_INVENTORY) --inventory "$$tmp_inventory" \
				$(VAULT_ARGS) --graph \
		)"; \
		printf '%s\n' "$$inventory_graph" | grep -F '@webservers:' >/dev/null; \
		printf '%s\n' "$$inventory_graph" | grep -F -- '|--hexlet-6-web-1' >/dev/null; \
		printf '%s\n' "$$inventory_graph" | grep -F -- '|--hexlet-6-web-2' >/dev/null; \
		chmod 0644 "$$tmp_inventory"; \
		mv -f -- "$$tmp_inventory" "$(INVENTORY)"; \
		trap - 0 1 2 15; \
		printf 'Updated %s from exact RUNNING project instances.\n' "$(INVENTORY)"

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
