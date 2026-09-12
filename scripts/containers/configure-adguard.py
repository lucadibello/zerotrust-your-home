#!/usr/bin/env python3
# Configure AdGuard Home trusted proxies, upstream DNS, and client subnets

import os
import re
import sys


def configure_adguard(conf_file: str, dns_domain: str, primary_dns: str, local_network: str) -> int:
    if not os.path.isfile(conf_file):
        return 0

    try:
        with open(conf_file, "r", encoding="utf-8") as f:
            content = f.read()
    except Exception as e:
        print(f"[-] Could not read {conf_file}: {e}", file=sys.stderr)
        return 0

    changed = False

    trusted_proxies_block = (
        "  trusted_proxies:\n"
        "    - 127.0.0.0/8\n"
        "    - ::1/128\n"
        "    - 10.0.0.0/8\n"
        "    - 172.16.0.0/12\n"
        f"    - {local_network}\n"
        "    - 100.64.0.0/10"
    )

    if "trusted_proxies:" in content:
        if "172.16.0.0/12" not in content or "10.0.0.0/8" not in content or local_network not in content:
            content = re.sub(r"  trusted_proxies:\n(    - [^\n]+\n)+", trusted_proxies_block + "\n", content)
            changed = True
    else:
        content = re.sub(r"^(dns:.*?\n)", r"\1" + trusted_proxies_block + "\n", content, flags=re.MULTILINE)
        changed = True

    upstream_entry = f"[/{dns_domain}/]{primary_dns}"
    if dns_domain and primary_dns and upstream_entry not in content:
        if re.search(r"  upstream_dns:\n", content):
            content = re.sub(r"(  upstream_dns:\n)", r"\1    - '" + upstream_entry + "'\n", content)
            changed = True

    allowed_match = re.search(r"  allowed_clients:\n((    - [^\n]+\n)+)", content)
    if allowed_match:
        current_allowed = allowed_match.group(1)
        needed_subnets = [
            local_network,
            "10.0.0.0/8",
            "172.16.0.0/12",
            "100.64.0.0/10",
        ]
        added = [f"    - {sub}\n" for sub in needed_subnets if sub not in current_allowed]
        if added:
            new_allowed = current_allowed + "".join(added)
            content = content.replace(allowed_match.group(0), f"  allowed_clients:\n{new_allowed}")
            changed = True

    if changed:
        try:
            with open(conf_file, "w", encoding="utf-8") as f:
                f.write(content)
            print(f"[OK] Enforced trusted_proxies and upstream configuration in {conf_file}")
            return 2
        except PermissionError:
            tmp_path = conf_file + ".tmp"
            try:
                with open(tmp_path, "w", encoding="utf-8") as f:
                    f.write(content)
                print(f"[*] Staged AdGuard configuration update to {tmp_path}")
                return 3
            except Exception as e:
                print(f"[-] Could not stage configuration update: {e}", file=sys.stderr)
                return 1

    return 0


def main() -> None:
    if len(sys.argv) < 5:
        print("Usage: configure-adguard.py <conf_file> <dns_domain> <primary_dns> <local_network>", file=sys.stderr)
        sys.exit(1)

    conf_file = sys.argv[1]
    dns_domain = sys.argv[2]
    primary_dns = sys.argv[3]
    local_network = sys.argv[4]

    code = configure_adguard(conf_file, dns_domain, primary_dns, local_network)
    sys.exit(code)


if __name__ == "__main__":
    main()
