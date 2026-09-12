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
        os.path.join(config_dir, "jellyfin", "data", "jellyfin.db"),
        os.path.join(config_dir, "jellyfin", "jellyfin.db"),
    ]
    db_path = None
    for p in db_paths:
        if os.path.exists(p):
            db_path = p
            break

    if not db_path:
        return False

    if os.path.exists(db_path):
        if not os.access(db_path, os.W_OK) or not os.access(os.path.dirname(db_path), os.W_OK):
            print(
                f"[*] Jellyfin database at {db_path} is owned by container (root); skipping host-level pre-configuration (media-provisioner container will sync it).",
                file=sys.stderr,
            )
            return True

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

        cur.execute("PRAGMA table_info(Users)")
        user_cols = {col[1] for col in cur.fetchall()}

        cur.execute(
            "SELECT name FROM sqlite_master WHERE type='table' AND name='Permissions'"
        )
        has_permissions = cur.fetchone() is not None
        has_row_version = False
        if has_permissions:
            cur.execute("PRAGMA table_info(Permissions)")
            cols = [col[1] for col in cur.fetchall()]
            has_row_version = "RowVersion" in cols

        if users:
            target_id = None
            for u in users:
                if u[1].lower() == username.lower():
                    target_id = u[0]
                    break

            update_clauses = ["Password = ?"]
            params = [password_hash]

            if not target_id:
                target_id = users[0][0]
                update_clauses.append("Username = ?")
                params.append(username)
                if "NormalizedUsername" in user_cols:
                    update_clauses.append("NormalizedUsername = ?")
                    params.append(username.upper())

            if "EasyPassword" in user_cols:
                update_clauses.append("EasyPassword = NULL")
            if "MustUpdatePassword" in user_cols:
                update_clauses.append("MustUpdatePassword = 0")
            if "InvalidLoginAttemptCount" in user_cols:
                update_clauses.append("InvalidLoginAttemptCount = 0")

            params.append(target_id)
            cur.execute(
                f"UPDATE Users SET {', '.join(update_clauses)} WHERE Id = ?",
                params,
            )

            if has_permissions:
                cur.execute(
                    "SELECT Id FROM Permissions WHERE UserId = ? AND Kind = 0",
                    (target_id,),
                )
                perm = cur.fetchone()
                if perm:
                    cur.execute(
                        "UPDATE Permissions SET Value = 1 WHERE Id = ?",
                        (perm[0],),
                    )
                else:
                    if has_row_version:
                        cur.execute(
                            "INSERT INTO Permissions (Kind, Value, UserId, RowVersion) VALUES (0, 1, ?, 1)",
                            (target_id,),
                        )
                    else:
                        cur.execute(
                            "INSERT INTO Permissions (Kind, Value, UserId) VALUES (0, 1, ?)",
                            (target_id,),
                        )

            conn.commit()
            conn.close()
            return True
        else:
            new_id = str(uuid.uuid4())
            candidate_fields = {
                "Id": new_id,
                "Username": username,
                "NormalizedUsername": username.upper(),
                "Password": password_hash,
                "MustUpdatePassword": 0,
                "InvalidLoginAttemptCount": 0,
                "MaxActiveSessions": 0,
                "SubtitleMode": 0,
                "PlayDefaultAudioTrack": 1,
                "DisplayMissingEpisodes": 0,
                "DisplayCollectionsView": 1,
                "EnableLocalPassword": 1,
                "HidePlayedInLatest": 0,
                "RememberAudioSelections": 1,
                "RememberSubtitleSelections": 1,
                "EnableNextEpisodeAutoPlay": 1,
                "EnableAutoLogin": 0,
                "EnableUserPreferenceAccess": 1,
                "SyncPlayAccess": 0,
                "AuthenticationProviderId": "Jellyfin.Server.Implementations.Users.DefaultAuthenticationProvider",
                "PasswordResetProviderId": "Jellyfin.Server.Implementations.Users.DefaultPasswordResetProvider",
                "RowVersion": 1,
                "InternalId": 1,
            }
            insert_cols = [c for c in candidate_fields if c in user_cols]
            placeholders = ", ".join(["?"] * len(insert_cols))
            col_names = ", ".join(insert_cols)
            cur.execute(
                f"INSERT INTO Users ({col_names}) VALUES ({placeholders})",
                [candidate_fields[c] for c in insert_cols],
            )
            if has_permissions:
                admin_permissions = [
                    0, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 21, 22, 23
                ]
                for p_kind in admin_permissions:
                    if has_row_version:
                        cur.execute(
                            "INSERT INTO Permissions (Kind, Value, UserId, RowVersion) VALUES (?, 1, ?, 1)",
                            (p_kind, new_id),
                        )
                    else:
                        cur.execute(
                            "INSERT INTO Permissions (Kind, Value, UserId) VALUES (?, 1, ?)",
                            (p_kind, new_id),
                        )
            conn.commit()
            conn.close()
            return True
    except sqlite3.OperationalError as e:
        if "readonly" in str(e).lower():
            print(
                f"[*] Jellyfin database at {db_path} is owned by container (root); skipping host-level pre-configuration (media-provisioner container will sync it).",
                file=sys.stderr,
            )
            return True
        print(f"[-] Error syncing Jellyfin database: {e}", file=sys.stderr)
        return False
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
