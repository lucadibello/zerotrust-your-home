#!/usr/bin/env python3
# Configure and link media services: Jellyfin, Radarr, Sonarr, Prowlarr, Seerr, Bazarr

import hashlib
import json
import os
import sqlite3
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
import uuid


def log(msg):
    timestamp = time.strftime("%Y-%m-%d %H:%M:%S")
    print(f"[{timestamp}] {msg}", flush=True)


def log_ok(msg):
    log(f"[OK] {msg}")


def log_warn(msg):
    log(f"[WARN] {msg}")


def log_err(msg):
    log(f"[ERROR] {msg}")


def request_json(url, method="GET", data=None, headers=None, timeout=15):
    if headers is None:
        headers = {}
    req_data = None
    if data is not None:
        req_data = json.dumps(data).encode("utf-8")
        if "Content-Type" not in headers:
            headers["Content-Type"] = "application/json"
    req = urllib.request.Request(url, data=req_data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            content = resp.read().decode("utf-8")
            if content:
                try:
                    return json.loads(content)
                except json.JSONDecodeError:
                    return content
            return {}
    except urllib.error.HTTPError as e:
        body = e.read().decode("utf-8", errors="replace")
        return {"_error": True, "code": e.code, "body": body}
    except Exception as e:
        return {"_error": True, "exception": str(e)}


def wait_for_service(name, check_fn, max_seconds=90, interval=3):
    start = time.time()
    while time.time() - start < max_seconds:
        try:
            if check_fn():
                log_ok(f"{name} is reachable and responding.")
                return True
        except Exception:
            pass
        time.sleep(interval)
    log_err(f"Timeout waiting for {name} after {max_seconds}s.")
    return False


def read_xml_key(config_path, tag="ApiKey"):
    if not os.path.exists(config_path):
        return None
    try:
        import xml.etree.ElementTree as ET

        tree = ET.parse(config_path)
        elem = tree.getroot().find(tag)
        if elem is not None and elem.text:
            return elem.text.strip()
    except Exception:
        pass
    return None


def read_bazarr_key(config_path):
    if not os.path.exists(config_path):
        return None
    try:
        with open(config_path, "r", encoding="utf-8") as f:
            in_auth = False
            for line in f:
                stripped = line.strip()
                if stripped == "auth:":
                    in_auth = True
                    continue
                if in_auth and stripped.startswith("apikey:"):
                    val = stripped.split(":", 1)[1].strip().strip("'\"")
                    if val:
                        return val
                elif in_auth and not line.startswith(" ") and not line.startswith("\t"):
                    in_auth = False
    except Exception:
        pass
    return None


def sync_jellyfin_admin_credentials(config_dir, username, password):
    db_paths = [
        os.path.join(config_dir, "jellyfin", "data", "jellyfin.db"),
        os.path.join(config_dir, "jellyfin", "jellyfin.db"),
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

        salt = os.urandom(16)
        key = hashlib.pbkdf2_hmac("sha512", password.encode("utf-8"), salt, 210000, 64)
        password_hash = f"$PBKDF2-SHA512$iterations=210000${salt.hex().upper()}${key.hex().upper()}"

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
            log("[*] Synchronized Jellyfin admin credentials in SQLite database.")
            return True
        else:
            new_id = str(uuid.uuid4())
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
            log("[*] Initialized Jellyfin admin user in SQLite database.")
            return True
    except Exception as e:
        log_warn(f"Failed to sync Jellyfin database: {e}")
        return False


def setup_jellyfin(config_dir, admin_user, admin_password):
    log("[*] Configuring Jellyfin...")
    public_info = request_json("http://jellyfin:8096/System/Info/Public")
    if public_info.get("_error"):
        log_err(f"Failed to query Jellyfin info: {public_info}")
        return None, None

    auth_header = (
        'MediaBrowser Client="ZeroTrustHome", Device="provisioner", '
        'DeviceId="provisioner-media", Version="1.0.0"'
    )
    auth_headers = {
        "Authorization": auth_header,
        "X-Emby-Authorization": auth_header,
    }

    is_wizard_done = public_info.get("StartupWizardCompleted", False)
    if not is_wizard_done:
        log("[*] Completing Jellyfin initial startup wizard...")
        request_json("http://jellyfin:8096/Startup/User", headers=auth_headers)
        request_json(
            "http://jellyfin:8096/Startup/User",
            method="POST",
            data={"Name": admin_user, "Password": admin_password},
            headers=auth_headers,
        )
        request_json(
            "http://jellyfin:8096/Startup/Complete",
            method="POST",
            headers=auth_headers,
        )
        time.sleep(2)

    auth_resp = request_json(
        "http://jellyfin:8096/Users/AuthenticateByName",
        method="POST",
        data={"Username": admin_user, "Pw": admin_password},
        headers=auth_headers,
    )

    if auth_resp.get("_error"):
        log("[*] Syncing Jellyfin admin credentials directly with database...")
        sync_jellyfin_admin_credentials(config_dir, admin_user, admin_password)
        request_json(
            "http://jellyfin:8096/Startup/Complete",
            method="POST",
            headers=auth_headers,
        )
        time.sleep(1)
        auth_resp = request_json(
            "http://jellyfin:8096/Users/AuthenticateByName",
            method="POST",
            data={"Username": admin_user, "Pw": admin_password},
            headers=auth_headers,
        )

    if auth_resp.get("_error"):
        log_err(
            f"Jellyfin authentication failed for user '{admin_user}': {auth_resp.get('body', auth_resp)}"
        )
        log_warn(
            "Verify JELLYFIN_ADMIN_USER and JELLYFIN_ADMIN_PASSWORD in .env match your Jellyfin administrator credentials."
        )
        return None, None

    token = auth_resp.get("AccessToken")
    server_id = auth_resp.get("ServerId") or public_info.get("Id")

    session_auth_header = f'{auth_header}, Token="{token}"'
    session_headers = {
        "Authorization": session_auth_header,
        "X-Emby-Authorization": session_auth_header,
        "X-Emby-Token": token,
    }

    # Ensure Seerr API key exists
    keys = request_json("http://jellyfin:8096/Auth/Keys", headers=session_headers)
    jellyfin_api_key = None
    if isinstance(keys, list):
        for k in keys:
            if k.get("AppName") == "Seerr":
                jellyfin_api_key = k.get("AccessToken")
                break

    if not jellyfin_api_key:
        request_json(
            "http://jellyfin:8096/Auth/Keys?app=Seerr",
            method="POST",
            headers=session_headers,
        )
        keys = request_json("http://jellyfin:8096/Auth/Keys", headers=session_headers)
        if isinstance(keys, list):
            for k in keys:
                if k.get("AppName") == "Seerr":
                    jellyfin_api_key = k.get("AccessToken")
                    break

    # Ensure Virtual Folders (Movies, TV Shows)
    folders = request_json(
        "http://jellyfin:8096/Library/VirtualFolders", headers=session_headers
    )
    folder_names = [f.get("Name") for f in folders] if isinstance(folders, list) else []

    if "Movies" not in folder_names:
        log("[*] Adding Movies library to Jellyfin...")
        request_json(
            "http://jellyfin:8096/Library/VirtualFolders?name=Movies&collectionType=movies&paths=%2Fmedia%2Fmovies&refreshLibrary=true",
            method="POST",
            headers=session_headers,
        )
    if "TV Shows" not in folder_names:
        log("[*] Adding TV Shows library to Jellyfin...")
        request_json(
            "http://jellyfin:8096/Library/VirtualFolders?name=TV+Shows&collectionType=tvshows&paths=%2Fmedia%2Ftv&refreshLibrary=true",
            method="POST",
            headers=session_headers,
        )

    log_ok("Jellyfin configured successfully.")
    return jellyfin_api_key, server_id


def setup_radarr(api_key, qbt_user="admin", qbt_pass=""):
    log("[*] Configuring Radarr...")
    headers = {"X-Api-Key": api_key}

    # 1. Root folder
    root_folders = request_json("http://radarr:7878/api/v3/rootfolder", headers=headers)
    has_movies_root = False
    if isinstance(root_folders, list):
        has_movies_root = any(rf.get("path") == "/media/movies" for rf in root_folders)

    if not has_movies_root:
        log("[*] Adding /media/movies root folder to Radarr...")
        request_json(
            "http://radarr:7878/api/v3/rootfolder",
            method="POST",
            data={"path": "/media/movies"},
            headers=headers,
        )

    # 2. qBittorrent download client
    clients = request_json("http://radarr:7878/api/v3/downloadclient", headers=headers)
    has_qbt = False
    if isinstance(clients, list):
        has_qbt = any(c.get("name") == "qBittorrent" for c in clients)

    if not has_qbt:
        log("[*] Adding qBittorrent download client to Radarr...")
        schema = request_json(
            "http://radarr:7878/api/v3/downloadclient/schema", headers=headers
        )
        qbt_schema = None
        if isinstance(schema, list):
            for s in schema:
                if s.get("implementation") == "QBittorrent":
                    qbt_schema = s
                    break

        if qbt_schema:
            qbt_schema["name"] = "qBittorrent"
            qbt_schema["enable"] = True
            for field in qbt_schema.get("fields", []):
                fname = field.get("name")
                if fname == "host":
                    field["value"] = "qbittorrent"
                elif fname == "port":
                    field["value"] = 8080
                elif fname == "useSsl":
                    field["value"] = False
                elif fname == "username":
                    field["value"] = qbt_user
                elif fname == "password":
                    field["value"] = qbt_pass
                elif fname == "movieCategory":
                    field["value"] = "radarr"
                elif fname == "initialState":
                    field["value"] = 0
            request_json(
                "http://radarr:7878/api/v3/downloadclient",
                method="POST",
                data=qbt_schema,
                headers=headers,
            )

    # 3. Media Management renaming
    mm = request_json(
        "http://radarr:7878/api/v3/config/mediamanagement", headers=headers
    )
    if isinstance(mm, dict) and not mm.get("_error"):
        if not mm.get("autoRenameFolders") or not mm.get("renameMovies"):
            mm["autoRenameFolders"] = True
            mm["renameMovies"] = True
            request_json(
                "http://radarr:7878/api/v3/config/mediamanagement",
                method="PUT",
                data=mm,
                headers=headers,
            )

    log_ok("Radarr configured successfully.")


def setup_sonarr(api_key, qbt_user="admin", qbt_pass=""):
    log("[*] Configuring Sonarr...")
    headers = {"X-Api-Key": api_key}

    # 1. Root folder
    root_folders = request_json("http://sonarr:8989/api/v3/rootfolder", headers=headers)
    has_tv_root = False
    if isinstance(root_folders, list):
        has_tv_root = any(rf.get("path") == "/media/tv" for rf in root_folders)

    if not has_tv_root:
        log("[*] Adding /media/tv root folder to Sonarr...")
        request_json(
            "http://sonarr:8989/api/v3/rootfolder",
            method="POST",
            data={"path": "/media/tv"},
            headers=headers,
        )

    # 2. qBittorrent download client
    clients = request_json("http://sonarr:8989/api/v3/downloadclient", headers=headers)
    has_qbt = False
    if isinstance(clients, list):
        has_qbt = any(c.get("name") == "qBittorrent" for c in clients)

    if not has_qbt:
        log("[*] Adding qBittorrent download client to Sonarr...")
        schema = request_json(
            "http://sonarr:8989/api/v3/downloadclient/schema", headers=headers
        )
        qbt_schema = None
        if isinstance(schema, list):
            for s in schema:
                if s.get("implementation") == "QBittorrent":
                    qbt_schema = s
                    break

        if qbt_schema:
            qbt_schema["name"] = "qBittorrent"
            qbt_schema["enable"] = True
            for field in qbt_schema.get("fields", []):
                fname = field.get("name")
                if fname == "host":
                    field["value"] = "qbittorrent"
                elif fname == "port":
                    field["value"] = 8080
                elif fname == "useSsl":
                    field["value"] = False
                elif fname == "username":
                    field["value"] = qbt_user
                elif fname == "password":
                    field["value"] = qbt_pass
                elif fname == "tvCategory":
                    field["value"] = "sonarr"
                elif fname == "initialState":
                    field["value"] = 0
            request_json(
                "http://sonarr:8989/api/v3/downloadclient",
                method="POST",
                data=qbt_schema,
                headers=headers,
            )

    # 3. Media Management renaming
    mm = request_json(
        "http://sonarr:8989/api/v3/config/mediamanagement", headers=headers
    )
    if isinstance(mm, dict) and not mm.get("_error"):
        if not mm.get("renameEpisodes") or not mm.get("createEmptySeriesFolders"):
            mm["renameEpisodes"] = True
            mm["createEmptySeriesFolders"] = True
            request_json(
                "http://sonarr:8989/api/v3/config/mediamanagement",
                method="PUT",
                data=mm,
                headers=headers,
            )

    log_ok("Sonarr configured successfully.")


def setup_prowlarr(prowlarr_key, radarr_key, sonarr_key):
    log("[*] Configuring Prowlarr...")
    headers = {"X-Api-Key": prowlarr_key}

    # 1. FlareSolverr proxy
    proxies = request_json("http://prowlarr:9696/api/v1/indexerproxy", headers=headers)
    has_flare = False
    if isinstance(proxies, list):
        has_flare = any(p.get("name") == "FlareSolverr" for p in proxies)

    if not has_flare:
        log("[*] Adding FlareSolverr proxy to Prowlarr...")
        schema = request_json(
            "http://prowlarr:9696/api/v1/indexerproxy/schema", headers=headers
        )
        flare_schema = None
        if isinstance(schema, list):
            for s in schema:
                if s.get("implementation") == "FlareSolverr":
                    flare_schema = s
                    break

        if flare_schema:
            flare_schema["name"] = "FlareSolverr"
            flare_schema["enable"] = True
            for field in flare_schema.get("fields", []):
                if field.get("name") == "host":
                    field["value"] = "http://flaresolverr:8191"
            request_json(
                "http://prowlarr:9696/api/v1/indexerproxy",
                method="POST",
                data=flare_schema,
                headers=headers,
            )

    # 2. Application sync (Radarr & Sonarr)
    apps = request_json("http://prowlarr:9696/api/v1/applications", headers=headers)
    app_names = [a.get("name") for a in apps] if isinstance(apps, list) else []

    app_schema = request_json(
        "http://prowlarr:9696/api/v1/applications/schema", headers=headers
    )

    if "Radarr" not in app_names and isinstance(app_schema, list):
        log("[*] Linking Radarr application sync to Prowlarr...")
        for s in app_schema:
            if s.get("implementation") == "Radarr":
                r_app = dict(s)
                r_app["name"] = "Radarr"
                r_app["syncLevel"] = "fullSync"
                for field in r_app.get("fields", []):
                    fname = field.get("name")
                    if fname == "prowlarrUrl":
                        field["value"] = "http://prowlarr:9696"
                    elif fname == "baseUrl":
                        field["value"] = "http://radarr:7878"
                    elif fname == "apiKey":
                        field["value"] = radarr_key
                request_json(
                    "http://prowlarr:9696/api/v1/applications",
                    method="POST",
                    data=r_app,
                    headers=headers,
                )
                break

    if "Sonarr" not in app_names and isinstance(app_schema, list):
        log("[*] Linking Sonarr application sync to Prowlarr...")
        for s in app_schema:
            if s.get("implementation") == "Sonarr":
                s_app = dict(s)
                s_app["name"] = "Sonarr"
                s_app["syncLevel"] = "fullSync"
                for field in s_app.get("fields", []):
                    fname = field.get("name")
                    if fname == "prowlarrUrl":
                        field["value"] = "http://prowlarr:9696"
                    elif fname == "baseUrl":
                        field["value"] = "http://sonarr:8989"
                    elif fname == "apiKey":
                        field["value"] = sonarr_key
                request_json(
                    "http://prowlarr:9696/api/v1/applications",
                    method="POST",
                    data=s_app,
                    headers=headers,
                )
                break

    log_ok("Prowlarr configured successfully.")


def setup_seerr(
    config_dir, dns_domain, jellyfin_key, server_id, radarr_key, sonarr_key
):
    log("[*] Configuring Seerr settings.json...")
    seerr_dir = os.path.join(config_dir, "seerr")
    os.makedirs(seerr_dir, exist_ok=True)
    settings_file = os.path.join(seerr_dir, "settings.json")

    settings = {}
    if os.path.exists(settings_file):
        try:
            with open(settings_file, "r", encoding="utf-8") as f:
                settings = json.load(f)
        except Exception:
            settings = {}

    if "main" not in settings:
        settings["main"] = {}
    settings["main"]["applicationTitle"] = "Seerr"
    settings["main"]["applicationUrl"] = f"https://seerr.{dns_domain}"
    settings["main"]["mediaServerType"] = 2
    settings["main"]["trustProxy"] = True

    if "jellyfin" not in settings:
        settings["jellyfin"] = {}
    settings["jellyfin"]["name"] = "Jellyfin"
    settings["jellyfin"]["ip"] = "jellyfin"
    settings["jellyfin"]["port"] = 8096
    settings["jellyfin"]["useSsl"] = False
    if jellyfin_key:
        settings["jellyfin"]["apiKey"] = jellyfin_key
    if server_id:
        settings["jellyfin"]["serverId"] = server_id

    # Radarr integration
    settings["radarr"] = [
        {
            "id": 0,
            "name": "Radarr",
            "hostname": "radarr",
            "port": 7878,
            "apiKey": radarr_key,
            "useSsl": False,
            "activeProfileId": 1,
            "activeProfileName": "Any",
            "activeDirectory": "/media/movies",
            "isDefault": True,
            "syncEnabled": True,
            "preventSearch": False,
        }
    ]

    # Sonarr integration
    settings["sonarr"] = [
        {
            "id": 0,
            "name": "Sonarr",
            "hostname": "sonarr",
            "port": 8989,
            "apiKey": sonarr_key,
            "useSsl": False,
            "activeProfileId": 1,
            "activeProfileName": "Any",
            "activeDirectory": "/media/tv",
            "isDefault": True,
            "syncEnabled": True,
            "preventSearch": False,
            "enableSeasonFolders": True,
        }
    ]

    with open(settings_file, "w", encoding="utf-8") as f:
        json.dump(settings, f, indent=2)

    log_ok("Seerr configuration persisted.")


def main():
    log("[*] Starting media stack auto-provisioning...")

    config_dir = os.getenv("CONFIG_DIR", "/config")
    radarr_key = (
        read_xml_key(os.path.join(config_dir, "radarr", "config.xml"))
        or os.getenv("RADARR_API_KEY", "")
    )
    sonarr_key = (
        read_xml_key(os.path.join(config_dir, "sonarr", "config.xml"))
        or os.getenv("SONARR_API_KEY", "")
    )
    prowlarr_key = (
        read_xml_key(os.path.join(config_dir, "prowlarr", "config.xml"))
        or os.getenv("PROWLARR_API_KEY", "")
    )
    bazarr_key = (
        read_bazarr_key(os.path.join(config_dir, "bazarr", "config", "config.yaml"))
        or os.getenv("BAZARR_API_KEY", "")
    )
    admin_user = os.getenv("JELLYFIN_ADMIN_USER", "admin")
    admin_pass = os.getenv("JELLYFIN_ADMIN_PASSWORD", "")
    qbt_user = os.getenv("QBITTORRENT_WEBUI_USERNAME", "admin")
    qbt_pass = os.getenv("QBITTORRENT_WEBUI_PASSWORD", "")
    dns_domain = os.getenv("DNS_DOMAIN", "home.lucadibello.ch")

    # Step 1: Wait for services to respond
    wait_for_service(
        "FlareSolverr",
        lambda: not request_json("http://flaresolverr:8191/").get("_error"),
    )

    def check_radarr():
        ping = request_json("http://radarr:7878/ping")
        if isinstance(ping, dict) and ping.get("status") == "OK":
            return True
        status = request_json(
            "http://radarr:7878/api/v3/system/status",
            headers={"X-Api-Key": radarr_key},
        )
        return not status.get("_error")

    wait_for_service("Radarr", check_radarr)

    def check_sonarr():
        ping = request_json("http://sonarr:8989/ping")
        if isinstance(ping, dict) and ping.get("status") == "OK":
            return True
        status = request_json(
            "http://sonarr:8989/api/v3/system/status",
            headers={"X-Api-Key": sonarr_key},
        )
        return not status.get("_error")

    wait_for_service("Sonarr", check_sonarr)

    def check_prowlarr():
        ping = request_json("http://prowlarr:9696/ping")
        if isinstance(ping, dict) and ping.get("status") == "OK":
            return True
        status = request_json(
            "http://prowlarr:9696/api/v1/system/status",
            headers={"X-Api-Key": prowlarr_key},
        )
        return not status.get("_error")

    wait_for_service("Prowlarr", check_prowlarr)

    wait_for_service(
        "Jellyfin",
        lambda: not request_json("http://jellyfin:8096/System/Info/Public").get(
            "_error"
        ),
    )

    def check_qbt():
        res = request_json("http://qbittorrent:8080/api/v2/app/version")
        if isinstance(res, str):
            return True
        if isinstance(res, dict):
            return res.get("code") in [200, 403] or not res.get("_error")
        return False

    wait_for_service("qBittorrent", check_qbt)

    def check_bazarr():
        ping = request_json("http://bazarr:6767/api/system/ping")
        if isinstance(ping, dict) and ping.get("status") == "OK":
            return True
        status = request_json(
            f"http://bazarr:6767/api/system/status?apikey={bazarr_key}",
            headers={"X-Api-Key": bazarr_key, "X-API-KEY": bazarr_key},
        )
        return not status.get("_error")

    wait_for_service("Bazarr", check_bazarr)

    wait_for_service(
        "Seerr",
        lambda: not request_json("http://seerr:5055/api/v1/status").get("_error"),
    )

    # Step 2: Configure Jellyfin & obtain API key
    jellyfin_key, server_id = setup_jellyfin(config_dir, admin_user, admin_pass)

    # Step 3: Configure Radarr with qBittorrent credentials
    setup_radarr(radarr_key, qbt_user, qbt_pass)

    # Step 4: Configure Sonarr with qBittorrent credentials
    setup_sonarr(sonarr_key, qbt_user, qbt_pass)

    # Step 5: Configure Prowlarr
    setup_prowlarr(prowlarr_key, radarr_key, sonarr_key)

    # Step 6: Configure Seerr
    setup_seerr(config_dir, dns_domain, jellyfin_key, server_id, radarr_key, sonarr_key)

    log("[*] Testing Bazarr status...")
    bazarr_status = request_json(
        f"http://bazarr:6767/api/system/status?apikey={bazarr_key}",
        headers={"X-Api-Key": bazarr_key, "X-API-KEY": bazarr_key},
    )
    if not bazarr_status.get("_error"):
        bv = (
            bazarr_status.get("data", {}).get("bazarr_version")
            if isinstance(bazarr_status, dict) and "data" in bazarr_status
            else bazarr_status.get("bazarr_version")
        )
        log_ok(f"Bazarr connected (version: {bv})")

    log_ok("Media stack configuration completed.")


if __name__ == "__main__":
    main()
