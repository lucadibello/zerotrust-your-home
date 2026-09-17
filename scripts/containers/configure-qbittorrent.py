#!/usr/bin/env python3
# Configure qBittorrent preferences and authentication credentials

import base64
import hashlib
import os
import sys


def hash_password(password: str) -> tuple[str, str]:
    salt = os.urandom(16)
    key = hashlib.pbkdf2_hmac(
        hash_name="sha512",
        password=password.encode("utf-8"),
        salt=salt,
        iterations=100000,
        dklen=64,
    )
    salt_b64 = base64.b64encode(salt).decode("ascii")
    key_b64 = base64.b64encode(key).decode("ascii")
    return salt_b64, key_b64


def configure_qbittorrent(conf_path: str, username: str, password: str) -> None:
    os.makedirs(os.path.dirname(conf_path), exist_ok=True)
    salt_b64, key_b64 = hash_password(password)

    user_line = r"WebUI\Username=" + username
    pass_line = f'WebUI\\Password_PBKDF2="@ByteArray({salt_b64}:{key_b64})"'

    required_pref_lines = {
        r"WebUI\Address=": r"WebUI\Address=*",
        r"WebUI\ServerDomains=": r"WebUI\ServerDomains=*",
        r"WebUI\HostHeaderValidation=": r"WebUI\HostHeaderValidation=false",
        r"WebUI\AuthSubnetWhitelistEnabled=": r"WebUI\AuthSubnetWhitelistEnabled=false",
        r"WebUI\AuthSubnetWhitelist=": r"WebUI\AuthSubnetWhitelist=",
        r"Downloads\SavePath=": r"Downloads\SavePath=/downloads/",
        r"Session\DefaultSavePath=": r"Session\DefaultSavePath=/downloads/",
        r"WebUI\Username=": user_line,
        r"WebUI\Password_PBKDF2=": pass_line,
    }

    if not os.path.exists(conf_path):
        lines = ["[LegalNotice]", "Accepted=true", "", "[Preferences]"]
        for val in required_pref_lines.values():
            lines.append(val)
        with open(conf_path, "w", encoding="utf-8") as f:
            f.write("\n".join(lines) + "\n")
        return

    with open(conf_path, "r", encoding="utf-8") as f:
        content = f.read()

    lines = content.splitlines()
    new_lines = []
    in_preferences = False
    has_preferences_section = any(l.strip() == "[Preferences]" for l in lines)
    seen_keys = set()

    def append_missing_pref_lines(target_list: list[str]) -> None:
        for key, val in required_pref_lines.items():
            if key not in seen_keys:
                target_list.append(val)
                seen_keys.add(key)

    for line in lines:
        stripped = line.strip()
        if stripped == "[Preferences]":
            in_preferences = True
            new_lines.append(line)
            continue
        elif stripped.startswith("[") and stripped != "[Preferences]":
            if in_preferences:
                append_missing_pref_lines(new_lines)
                in_preferences = False

        matched = False
        if in_preferences:
            for key, val in required_pref_lines.items():
                if line.startswith(key):
                    new_lines.append(val)
                    seen_keys.add(key)
                    matched = True
                    break

        if not matched:
            new_lines.append(line)

    if in_preferences:
        append_missing_pref_lines(new_lines)

    if not has_preferences_section:
        if new_lines and new_lines[-1] != "":
            new_lines.append("")
        new_lines.append("[Preferences]")
        append_missing_pref_lines(new_lines)

    content_str = "\n".join(new_lines)
    if "[LegalNotice]" not in content_str:
        new_lines.insert(0, "")
        new_lines.insert(0, "Accepted=true")
        new_lines.insert(0, "[LegalNotice]")

    with open(conf_path, "w", encoding="utf-8") as f:
        f.write("\n".join(new_lines) + "\n")


def main() -> None:
    if len(sys.argv) < 4:
        print("Usage: configure-qbittorrent.py <conf_path> <username> <password>", file=sys.stderr)
        sys.exit(1)

    conf_path = sys.argv[1]
    username = sys.argv[2]
    password = sys.argv[3]

    configure_qbittorrent(conf_path, username, password)


if __name__ == "__main__":
    main()
