#!/usr/bin/env python3
# Configure Jellyfin administrator credentials

import hashlib
import os
import sqlite3
import sys
import uuid


def hash_jellyfin_password(password: str) -> str:
    salt = os.urandom(16)
    key = hashlib.pbkdf2_hmac("sha512", password.encode("utf-8"), salt, 210000, 64)
    return f"$PBKDF2-SHA512$iterations=210000${salt.hex().upper()}${key.hex().upper()}"


def configure_jellyfin(config_dir: str, username: str, password: str) -> bool:
    db_paths = [
        os.path.join(config_dir, "data", "jellyfin.db"),
        os.path.join(config_dir, "jellyfin.db"),
    ]
    db_path = None
    for p in db_paths:
        if os.path.exists(p):
            db_path = p
            break

    if not db_path:
        return False

    try:
        conn = sqlite3.connect(db_path)
        cur = conn.cursor()

        cur.execute(
            "SELECT name FROM sqlite_master WHERE type='table' AND name='Users'"
        )
        if not cur.fetchone():
            conn.close()
            return False

        cur.execute("SELECT Id, Username, Password FROM Users")
        users = cur.fetchall()

        password_hash = hash_jellyfin_password(password)

        if users:
            target_id = None
            for u in users:
                if u[1].lower() == username.lower():
                    target_id = u[0]
                    break

            if target_id:
                cur.execute(
                    "UPDATE Users SET Password = ?, EasyPassword = NULL, MustUpdatePassword = 0, InvalidLoginAttemptCount = 0 WHERE Id = ?",
                    (password_hash, target_id),
                )
            else:
                target_id = users[0][0]
                cur.execute(
                    "UPDATE Users SET Username = ?, NormalizedUsername = ?, Password = ?, EasyPassword = NULL, MustUpdatePassword = 0, InvalidLoginAttemptCount = 0 WHERE Id = ?",
                    (username, username.upper(), password_hash, target_id),
                )
            conn.commit()
            conn.close()
            return True
        else:
            new_id = str(uuid.uuid4()).replace("-", "")
            cur.execute(
                """
                INSERT INTO Users (
                    Id, Username, NormalizedUsername, Password,
                    MustUpdatePassword, InvalidLoginAttemptCount, MaxActiveSessions,
                    SubtitleMode, PlayDefaultAudioTrack, DisplayMissingEpisodes,
                    DisplayCollectionsView, EnableLocalPassword, HidePlayedInLatest,
                    RememberAudioSelections, RememberSubtitleSelections,
                    EnableNextEpisodeAutoPlay, EnableAutoLogin, EnableUserPreferenceAccess,
                    SyncPlayAccess, AuthenticationProviderId, PasswordResetProviderId,
                    RowVersion, InternalId
                ) VALUES (
                    ?, ?, ?, ?,
                    0, 0, 0,
                    0, 1, 0,
                    1, 1, 0,
                    1, 1,
                    1, 0, 1,
                    0, 'Jellyfin.Server.Implementations.Users.DefaultAuthenticationProvider',
                    'Jellyfin.Server.Implementations.Users.DefaultPasswordResetProvider',
                    1, 1
                )
                """,
                (new_id, username, username.upper(), password_hash),
            )
            cur.execute(
                "SELECT name FROM sqlite_master WHERE type='table' AND name='Permissions'"
            )
            if cur.fetchone():
                cur.execute(
                    "INSERT INTO Permissions (Kind, Value, UserId) VALUES (0, 1, ?)",
                    (new_id,),
                )
            conn.commit()
            conn.close()
            return True
    except Exception as e:
        print(f"[-] Error syncing Jellyfin database: {e}", file=sys.stderr)
        return False


def main() -> None:
    if len(sys.argv) < 4:
        print(
            "Usage: configure-jellyfin.py <jellyfin_config_dir> <username> <password>",
            file=sys.stderr,
        )
        sys.exit(1)

    config_dir = sys.argv[1]
    username = sys.argv[2]
    password = sys.argv[3]

    success = configure_jellyfin(config_dir, username, password)
    if success:
        print(f"[OK] Successfully configured Jellyfin credentials for '{username}'")
    else:
        print(f"[*] Jellyfin database not yet initialized in {config_dir}")


if __name__ == "__main__":
    main()
