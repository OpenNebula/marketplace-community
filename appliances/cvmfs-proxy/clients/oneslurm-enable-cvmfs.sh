#!/usr/bin/env bash
# Makes a copy of a OneSlurm service template whose roles run oneslurm-start.sh at boot, so
# every worker of the cluster gets the CernVM-FS client and the EESSI configuration.
#
# Usage, on the Front-end as oneadmin, with oneslurm-start.sh in the same directory:
#   bash oneslurm-enable-cvmfs.sh <OneSlurm service template ID>
# It prints the ID of the new service template. Instantiate it and write the URL of the
# CernVM-FS proxy in its CVMFS_HTTP_PROXY input.
set -euo pipefail

src="${1:?usage: $0 <OneSlurm service template ID>}"
dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[[ -r "${dir}/oneslurm-start.sh" ]] || { echo "oneslurm-start.sh must be in ${dir}" >&2; exit 1; }

name="$(oneflow-template show "$src" -j | ruby -rjson -e 'puts JSON.parse($stdin.read)["DOCUMENT"]["NAME"]') with CernVM-FS"
new="$(oneflow-template clone "$src" "$name" | grep -oE '[0-9]+$')"

body="$(mktemp)"
trap 'rm -f "$body"' EXIT

# The body of the copy gets a mandatory input for the proxy URL, which OneFlow adds to the
# CONTEXT of every role, and the start script in the CONTEXT of both roles. OneFlow merges
# template_contents into the VM templates of the roles, so the rest of their CONTEXT stays.
oneflow-template show "$new" -j \
    | START="$(base64 -w0 "${dir}/oneslurm-start.sh")" NAME="$name" ruby -rjson -e '
        body = JSON.parse($stdin.read)["DOCUMENT"]["TEMPLATE"]["BODY"]
        body.delete("registration_time")
        body["name"] = ENV["NAME"]
        (body["user_inputs"] ||= {})["CVMFS_HTTP_PROXY"] =
            "M|text|URL of the CernVM-FS proxy, for example http://192.168.100.191:3128||"
        body["roles"].each do |role|
            contents = (role["template_contents"] ||= {})
            (contents["CONTEXT"] ||= {})["START_SCRIPT_BASE64"] = ENV["START"]
        end
        puts JSON.generate(body)' > "$body"

oneflow-template update "$new" "$body" >/dev/null
echo "$new"
