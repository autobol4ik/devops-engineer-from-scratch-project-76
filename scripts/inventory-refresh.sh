#!/bin/sh
# shellcheck disable=SC2016

set -eu

folder_id=${PROJECT6_FOLDER_ID:-}
inventory=${INVENTORY:-inventory.ini}
ssh_private_key_file=${INVENTORY_SSH_PRIVATE_KEY_FILE:-~/.ssh/hexlet-6-ansible}
yc=${YC:-yc}
jq=${JQ:-jq}
ansible_inventory=${ANSIBLE_INVENTORY:-ansible-inventory}

if [ -z "$folder_id" ]; then
	echo "Set PROJECT6_FOLDER_ID to the exact Yandex Cloud folder ID" >&2
	exit 1
fi

command -v "$yc" >/dev/null 2>&1 ||
	{ echo "Yandex Cloud CLI is unavailable: $yc" >&2; exit 1; }
command -v "$jq" >/dev/null 2>&1 ||
	{ echo "jq is unavailable: $jq" >&2; exit 1; }

instances_json=$("$yc" compute instance list \
	--folder-id "$folder_id" --format json)
printf '%s\n' "$instances_json" | "$jq" -e \
	'type == "array"' >/dev/null ||
	{ echo "Yandex Cloud CLI returned an invalid instance list" >&2; exit 1; }

instance_ip() {
	host_name=$1
	exact_matches=$(printf '%s\n' "$instances_json" |
		"$jq" -c --arg name "$host_name" \
			'[.[] | select(.name == $name)]')
	match_count=$(printf '%s\n' "$exact_matches" |
		"$jq" -r 'length')
	if [ "$match_count" -ne 1 ]; then
		echo "Expected exactly one RUNNING instance named $host_name, found $match_count" >&2
		return 1
	fi
	status=$(printf '%s\n' "$exact_matches" |
		"$jq" -r '.[0].status // empty')
	if [ "$status" != "RUNNING" ]; then
		echo "Instance $host_name is not RUNNING: ${status:-unknown}" >&2
		return 1
	fi
	address=$(printf '%s\n' "$exact_matches" | "$jq" -r \
		'.[0].network_interfaces[0].primary_v4_address.one_to_one_nat.address // empty')
	if ! "$jq" -en --arg address "$address" \
		'($address | split(".")) as $octets | ($octets | length == 4) and all($octets[]; test("^[0-9]{1,3}$") and ((tonumber >= 0) and (tonumber <= 255)))' \
		>/dev/null; then
		echo "Instance $host_name has no valid public IPv4" >&2
		return 1
	fi
	printf '%s\n' "$address"
}

web_1_ip=$(instance_ip hexlet-6-web-1)
web_2_ip=$(instance_ip hexlet-6-web-2)
inventory_dir=$(dirname -- "$inventory")
inventory_name=$(basename -- "$inventory")
tmp_inventory=$(mktemp "$inventory_dir/.$inventory_name.XXXXXX")
trap 'rm -f -- "$tmp_inventory"' 0 1 2 15

{
	printf '[webservers]\n'
	printf '%s ansible_host=%s ansible_user=ubuntu ansible_ssh_private_key_file=%s\n' \
		hexlet-6-web-1 "$web_1_ip" "$ssh_private_key_file"
	printf '%s ansible_host=%s ansible_user=ubuntu ansible_ssh_private_key_file=%s\n' \
		hexlet-6-web-2 "$web_2_ip" "$ssh_private_key_file"
} >"$tmp_inventory"

chmod 0600 "$tmp_inventory"
inventory_graph=$(
	"$ansible_inventory" --inventory "$tmp_inventory" "$@" --graph
)
printf '%s\n' "$inventory_graph" | grep -F '@webservers:' >/dev/null
printf '%s\n' "$inventory_graph" | grep -F -- '|--hexlet-6-web-1' >/dev/null
printf '%s\n' "$inventory_graph" | grep -F -- '|--hexlet-6-web-2' >/dev/null

chmod 0644 "$tmp_inventory"
mv -f -- "$tmp_inventory" "$inventory"
trap - 0 1 2 15
printf 'Updated %s from exact RUNNING project instances.\n' "$inventory"
