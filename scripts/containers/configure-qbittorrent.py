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

    if not os.path.exists(conf_path):
        content = (
            "[Preferences]\n"
            "WebUI\\HostHeaderValidation=false\n"
            "WebUI\\AuthSubnetWhitelistEnabled=false\n"
            "WebUI\\AuthSubnetWhitelist=\n"
            "Downloads\\SavePath=/downloads/\n"
            "Session\\DefaultSavePath=/downloads/\n"
            f"{user_line}\n"
            f"{pass_line}\n"
        )
        with open(conf_path, "w", encoding="utf-8") as f:
            f.write(content)
        return

    with open(conf_path, "r", encoding="utf-8") as f:
        content = f.read()

    lines = content.splitlines()
    new_lines = []
    in_preferences = False
    seen_user = False
    seen_pass = False

    for line in lines:
        stripped = line.strip()
        if stripped == "[Preferences]":
            in_preferences = True
            new_lines.append(line)
            continue
        elif stripped.startswith("[") and stripped != "[Preferences]":
            if in_preferences:
                if not seen_user:
                    new_lines.append(user_line)
                    seen_user = True
                if not seen_pass:
                    new_lines.append(pass_line)
                    seen_pass = True
                in_preferences = False

        if line.startswith(r"WebUI\HostHeaderValidation="):
            new_lines.append(r"WebUI\HostHeaderValidation=false")
        elif line.startswith(r"WebUI\AuthSubnetWhitelistEnabled="):
            new_lines.append(r"WebUI\AuthSubnetWhitelistEnabled=false")
        elif line.startswith(r"WebUI\AuthSubnetWhitelist="):
            new_lines.append(r"WebUI\AuthSubnetWhitelist=")
        elif line.startswith(r"WebUI\Username="):
            new_lines.append(user_line)
            seen_user = True
        elif line.startswith(r"WebUI\Password_PBKDF2="):
            new_lines.append(pass_line)
            seen_pass = True
        else:
            new_lines.append(line)

    if in_preferences:
        if not seen_user:
            new_lines.append(user_line)
        if not seen_pass:
            new_lines.append(pass_line)

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
