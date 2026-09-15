import os
import sys
import shutil
import json
import getpass
import time
import re
from pathlib import Path
from datetime import datetime, timezone
import requests
from dotenv import load_dotenv
from google.oauth2 import service_account
from googleapiclient.discovery import build
from googleapiclient.http import MediaIoBaseUpload
from io import BytesIO
from concurrent.futures import ThreadPoolExecutor, as_completed
from threading import Lock

# Ensure backend directory is in sys.path for module resolution
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from typing import List, Optional, Dict, Any

from fastapi import (
    FastAPI,
    UploadFile,
    File,
    Query,
    HTTPException
)

from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from fastapi.responses import FileResponse
from pydantic import BaseModel

from excel_parser import (
    generate_sample_schnell_iot_data,
    compute_pending_poles,
    parse_excel_dataset,
    haversine_distance,
    classify_old_lamp,
    normalize_lamp_type
)


# ============================================================
# FASTAPI APP
# ============================================================

app = FastAPI(
    title="BBMP Pending Poles API",
    description=(
        "Backend API for computing pending poles "
        "(Master Survey Data - Lamp Installation Report), "
        "region/zone/ward filtering, geographical distance "
        "calculation, and Schnell IoT / ThingsBoard integration."
    ),
    version="2.4.0"
)


# ============================================================
# TECHNICIAN IMAGE STORAGE (STAGING)
# ============================================================

BASE_DIR = Path(__file__).resolve().parent
POLE_IMAGES_DIR = BASE_DIR / "pole_images"
POLE_IMAGES_DIR.mkdir(parents=True, exist_ok=True)

# Images are exposed through the backend only after successful upload.
app.mount(
    "/pole-images",
    StaticFiles(directory=str(POLE_IMAGES_DIR)),
    name="pole-images",
)

ALLOWED_IMAGE_EXTENSIONS = {".jpg", ".jpeg", ".png", ".webp"}
MAX_IMAGE_SIZE_BYTES = 10 * 1024 * 1024

# Google Drive / Sheets configuration. This is used only for technician images.
load_dotenv(BASE_DIR / ".env")
load_dotenv(BASE_DIR.parent / ".env")
GOOGLE_SERVICE_ACCOUNT_FILE = os.getenv(
    "GOOGLE_SERVICE_ACCOUNT_FILE", "credentials/google-service-account.json"
)
GOOGLE_DRIVE_FOLDER_ID = os.getenv("GOOGLE_DRIVE_FOLDER_ID", "").strip()
GOOGLE_SHEET_ID = os.getenv("GOOGLE_SHEET_ID", "").strip()
GOOGLE_SHEET_NAME = os.getenv("GOOGLE_SHEET_NAME", "Sheet1").strip() or "Sheet1"

_google_services = None
_google_services_lock = Lock()

def _get_google_services():
    global _google_services
    if _google_services is not None:
        return _google_services
    with _google_services_lock:
        if _google_services is None:
            credentials_path = Path(GOOGLE_SERVICE_ACCOUNT_FILE)
            if not credentials_path.is_absolute():
                credentials_path = BASE_DIR / credentials_path
            if not credentials_path.exists():
                raise RuntimeError(f"Google service-account file not found: {credentials_path}")
            if not GOOGLE_DRIVE_FOLDER_ID or not GOOGLE_SHEET_ID:
                raise RuntimeError("GOOGLE_DRIVE_FOLDER_ID and GOOGLE_SHEET_ID must be set in .env")
            credentials = service_account.Credentials.from_service_account_file(
                str(credentials_path),
                scopes=[
                    "https://www.googleapis.com/auth/drive",
                    "https://www.googleapis.com/auth/spreadsheets",
                ],
            )
            _google_services = (
                build("drive", "v3", credentials=credentials, cache_discovery=False),
                build("sheets", "v4", credentials=credentials, cache_discovery=False),
            )
    return _google_services

def _drive_upload_image(contents: bytes, filename: str, mime_type: str, pole_number: str, image_slot: int) -> str:
    drive_service, _ = _get_google_services()
    safe_name = f"{_safe_pole_folder_name(pole_number)}_image_{image_slot}{Path(filename).suffix.lower()}"
    media = MediaIoBaseUpload(BytesIO(contents), mimetype=mime_type or "application/octet-stream", resumable=False)
    created = drive_service.files().create(
        body={"name": safe_name, "parents": [GOOGLE_DRIVE_FOLDER_ID]},
        media_body=media,
        fields="id,webViewLink,webContentLink",
        supportsAllDrives=True,
    ).execute()
    file_id = created["id"]
    try:
        drive_service.permissions().create(
            fileId=file_id,
            body={"type": "anyone", "role": "reader"},
            fields="id",
            supportsAllDrives=True,
        ).execute()
    except Exception:
        # Some Shared Drives restrict public-link permissions. The upload
        # itself is still valid, so keep the Drive file URL.
        pass
    return f"https://drive.google.com/file/d/{file_id}/view"

def _update_sheet_image_link(pole_number: str, image_slot: int, drive_url: str) -> None:
    _, sheets_service = _get_google_services()
    result = sheets_service.spreadsheets().values().get(
        spreadsheetId=GOOGLE_SHEET_ID,
        range=f"'{GOOGLE_SHEET_NAME}'!A:ZZ",
    ).execute()
    rows = result.get("values", [])
    if not rows:
        raise RuntimeError("Google Sheet is empty. Add a header row and pole data first.")
    headers = [str(v).strip() for v in rows[0]]
    pole_col = next((i for i, h in enumerate(headers) if h.casefold() in {"pole number", "pole_number", "poleno", "pole no", "pole"}), None)
    if pole_col is None:
        raise RuntimeError("Google Sheet must contain a 'Pole Number' column.")
    image_header = f"Image {image_slot}"
    image_col = next((i for i, h in enumerate(headers) if h.casefold() == image_header.casefold()), None)
    if image_col is None:
        image_col = len(headers)
        sheets_service.spreadsheets().values().update(
            spreadsheetId=GOOGLE_SHEET_ID,
            range=f"'{GOOGLE_SHEET_NAME}'!{chr(65 + image_col)}1",
            valueInputOption="RAW",
            body={"values": [[image_header]]},
        ).execute()
    target_row = None
    wanted = _normalize_pole_number(pole_number).casefold()
    for row_index, row in enumerate(rows[1:], start=2):
        if pole_col < len(row) and _normalize_pole_number(row[pole_col]).casefold() == wanted:
            target_row = row_index
            break
    if target_row is None:
        raise RuntimeError(f"Pole {pole_number} was not found in Google Sheet.")
    def col_letter(n):
        out = ""
        n += 1
        while n:
            n, rem = divmod(n - 1, 26)
            out = chr(65 + rem) + out
        return out
    sheets_service.spreadsheets().values().update(
        spreadsheetId=GOOGLE_SHEET_ID,
        range=f"'{GOOGLE_SHEET_NAME}'!{col_letter(image_col)}{target_row}",
        valueInputOption="RAW",
        body={"values": [[drive_url]]},
    ).execute()


def _safe_pole_folder_name(pole_number: str) -> str:
    """Keep technician image folders safe and deterministic."""
    value = str(pole_number or "").strip()
    return re.sub(r"[^A-Za-z0-9._-]", "_", value)


def _find_live_pending_pole(pole_number: str) -> Optional[Dict[str, Any]]:
    """Find a pole in the current live pending-pole dataset."""
    normalized = _normalize_pole_number(pole_number)
    if not normalized:
        return None

    for pole in _get_live_pending_records():
        if _normalize_pole_number(pole.get("pole_number")) == normalized:
            return pole

    return None


def _read_image_metadata(pole_folder: Path) -> Dict[str, Any]:
    metadata_path = pole_folder / "metadata.json"

    if not metadata_path.exists():
        return {}

    try:
        value = json.loads(metadata_path.read_text(encoding="utf-8"))
        return value if isinstance(value, dict) else {}
    except (OSError, ValueError, TypeError):
        return {}


def _write_image_metadata(pole_folder: Path, metadata: Dict[str, Any]) -> None:
    metadata_path = pole_folder / "metadata.json"
    metadata_path.write_text(
        json.dumps(metadata, indent=2, ensure_ascii=False),
        encoding="utf-8",
    )


app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"]
)


# ============================================================
# SAMPLE DATA
# ============================================================

_INITIAL_IOT_DATA = generate_sample_schnell_iot_data()

MASTER_POLES_DATA: List[Dict[str, Any]] = (
    _INITIAL_IOT_DATA["master_poles"]
)

INSTALLED_REPORT_DATA: List[str] = (
    _INITIAL_IOT_DATA["installed_report"]
)

PENDING_POLES_DATA: List[Dict[str, Any]] = (
    _INITIAL_IOT_DATA["pending_poles"]
)


# ============================================================
# REQUEST MODELS
# ============================================================

class FilterRequest(BaseModel):
    region: Optional[str] = None
    zone: Optional[str] = None
    ward: Optional[str] = None
    pole_old_lamp: Optional[str] = None
    lamp_type: Optional[str] = None


class DistanceRequest(BaseModel):
    starting_pole_number: str
    filtered_pole_ids: Optional[List[int]] = None
    region: Optional[str] = None
    zone: Optional[str] = None
    ward: Optional[str] = None
    pole_old_lamp: Optional[str] = None
    lamp_type: Optional[str] = None


class InstalledReportSyncRequest(BaseModel):
    installed_pole_numbers: List[str]


class TechnicianImageMetadata(BaseModel):
    pole_number: str
    latitude: float
    longitude: float
    image_slot: int


# ============================================================
# HELPER FUNCTIONS
# ============================================================

def format_distance(meters: float) -> str:
    if meters >= 1000.0:
        return f"{meters / 1000.0:.2f} km"

    return f"{int(round(meters))} m"


def _recompute_pending():
    global PENDING_POLES_DATA

    PENDING_POLES_DATA = compute_pending_poles(
        MASTER_POLES_DATA,
        INSTALLED_REPORT_DATA
    )


# ============================================================
# SCHNELL IOT / THINGSBOARD CONFIGURATION
# ============================================================

TB_URL = os.getenv("THINGSBOARD_URL", "https://schnelliot.in").strip().rstrip("/")

# These IDs identify the ThingsBoard hierarchy used by the BBMP project.
EAST_ID = "401219c0-45c4-11f0-94dc-77130b2f47e9"
BOMMANAHALI_ID = "21456730-5bff-11f0-9e1d-abd300900bde"
BANGALORE_ID = "e2119df0-45c3-11f0-94dc-77130b2f47e9"

def get_schnell_iot_credentials():
    """Return ThingsBoard credentials from environment variables with fallback defaults."""
    username = (
        os.getenv("THINGSBOARD_USERNAME")
        or os.getenv("SCHNELL_IOT_EMAIL")
        or "projects_office01@schnellenergy.com"
    ).strip()
    password = (
        os.getenv("THINGSBOARD_PASSWORD")
        or os.getenv("SCHNELL_IOT_PASSWORD")
        or "Off!Ce2"
    )
    return username, password


# ============================================================
# SCHNELL IOT LOGIN
# ============================================================

def schnell_iot_login() -> str:
    """
    Login to Schnell IoT / ThingsBoard.

    Returns the JWT token.
    """

    email, password = get_schnell_iot_credentials()

    if not email or not password:
        raise HTTPException(
            status_code=503,
            detail=(
                "Schnell IoT credentials are not available. "
                "Restart the backend and enter the credentials."
            )
        )

    login_url = f"{TB_URL}/api/auth/login"

    payload = {
        "username": email,
        "password": password
    }

    try:

        response = requests.post(
            login_url,
            json=payload,
            timeout=(8, 20)
        )

    except requests.RequestException as exc:

        raise HTTPException(
            status_code=502,
            detail=(
                "Unable to connect to Schnell IoT login API: "
                f"{str(exc)}"
            )
        )

    if response.status_code != 200:

        raise HTTPException(
            status_code=401,
            detail=(
                "Schnell IoT login failed. "
                f"HTTP {response.status_code}: "
                f"{response.text[:500]}"
            )
        )

    try:

        response_json = response.json()

    except ValueError:

        raise HTTPException(
            status_code=502,
            detail=(
                "Schnell IoT login returned invalid JSON."
            )
        )

    token = response_json.get("token")

    if not token:

        raise HTTPException(
            status_code=502,
            detail=(
                "Schnell IoT login succeeded but "
                "no authentication token was returned."
            )
        )

    return token


# ============================================================
# THINGSBOARD POLE QUERY
# ============================================================

def fetch_real_pole_assets(
    token: str,
    max_poles: int = 5
) -> Dict[str, Any]:
    """
    Fetch real pole assets from ThingsBoard.

    This is currently a TEST operation.
    It does not modify the sample dataset.
    """

    url = f"{TB_URL}/api/entitiesQuery/find"

    headers = {
        "X-Authorization": f"Bearer {token}",
        "Content-Type": "application/json"
    }

    payload = {
        "entityFilter": {
            "type": "assetSearchQuery",
            "rootEntity": {
                "entityType": "ASSET",
                "id": EAST_ID
            },
            "direction": "FROM",
            "maxLevel": 5,
            "fetchLastLevelOnly": False,
            "relationType": "Contains",
            "assetTypes": [
                "pole"
            ]
        },
        "entityFields": [
            {
                "type": "ENTITY_FIELD",
                "key": "name"
            }
        ],
        "latestValues": [
            {
                "type": "ATTRIBUTE",
                "key": "lampProfiles"
            }
        ],
        "pageLink": {
            "pageSize": max_poles,
            "page": 0
        }
    }

    try:

        response = requests.post(
            url,
            headers=headers,
            json=payload,
            timeout=30
        )

    except requests.RequestException as exc:

        raise HTTPException(
            status_code=502,
            detail=(
                "ThingsBoard pole query failed: "
                f"{str(exc)}"
            )
        )

    if response.status_code != 200:

        raise HTTPException(
            status_code=502,
            detail=(
                "ThingsBoard pole query returned HTTP "
                f"{response.status_code}: "
                f"{response.text[:1000]}"
            )
        )

    try:

        return response.json()

    except ValueError:

        raise HTTPException(
            status_code=502,
            detail=(
                "ThingsBoard pole query returned "
                "invalid JSON."
            )
        )


# ============================================================
# THINGSBOARD VALUE EXTRACTION
# ============================================================

def extract_latest_value(entity: Dict[str, Any], key: str) -> Any:
    """
    Extract a value from the ThingsBoard /api/entitiesQuery/find
    response.

    In the Schnell IoT response, latest values are grouped by type:

        latest -> ATTRIBUTE -> lampProfiles -> {ts, value}
        latest -> ENTITY_FIELD -> name -> {ts, value}

    Keep fallbacks for alternate ThingsBoard response shapes as well.
    """
    latest = entity.get("latest")

    if isinstance(latest, dict):
        # Normal Schnell IoT response shape.
        for category in ("ATTRIBUTE", "ENTITY_FIELD", "SERVER_ATTRIBUTE", "SHARED_ATTRIBUTE"):
            category_values = latest.get(category)
            if isinstance(category_values, dict) and key in category_values:
                value = category_values.get(key)
                if isinstance(value, dict) and "value" in value:
                    return value.get("value")
                return value

        # Fallback: key directly under latest.
        value = latest.get(key)
        if isinstance(value, dict) and "value" in value:
            return value.get("value")
        if value is not None:
            return value

    elif isinstance(latest, list):
        for item in latest:
            if isinstance(item, dict) and item.get("key") == key:
                return item.get("value")

    # Fallback for responses where attributes are exposed through readAttrs.
    read_attrs = entity.get("readAttrs")
    if isinstance(read_attrs, dict):
        value = read_attrs.get(key)
        if isinstance(value, dict) and "value" in value:
            return value.get("value")
        if value is not None:
            return value

    if isinstance(read_attrs, list):
        for item in read_attrs:
            if isinstance(item, dict) and item.get("key") == key:
                return item.get("value")

    return None


def extract_entity_id(entity: Dict[str, Any]) -> Optional[str]:
    value = entity.get("entityId")

    if isinstance(value, dict):
        value = value.get("id") or value.get("entityId")

    if value is None:
        value = entity.get("id")
        if isinstance(value, dict):
            value = value.get("id")

    return str(value) if value is not None else None


def extract_entity_name(entity: Dict[str, Any]) -> Optional[str]:
    # Normal Schnell IoT response has the asset name here:
    # latest -> ENTITY_FIELD -> name -> {ts, value}
    name = extract_latest_value(entity, "name")
    if name is not None:
        return str(name)

    # Fallbacks for other response shapes.
    for key in ("name", "entityName"):
        value = entity.get(key)
        if value is not None:
            return str(value)

    attrs = entity.get("readAttrs")
    if isinstance(attrs, dict):
        value = attrs.get("name")
        if isinstance(value, dict):
            value = value.get("value")
        if value is not None:
            return str(value)

    if isinstance(attrs, list):
        for item in attrs:
            if isinstance(item, dict) and item.get("key") == "name":
                value = item.get("value")
                if value is not None:
                    return str(value)

    return None


def simplify_real_pole(entity: Dict[str, Any]) -> Dict[str, Any]:
    entity_id = entity.get("entityId")

    entity_type = (
        entity_id.get("entityType")
        if isinstance(entity_id, dict)
        else entity.get("entityType")
    )

    lamp_profiles = extract_latest_value(
        entity,
        "lampProfiles"
    )

    parsed_lamp_profiles = lamp_profiles

    if isinstance(lamp_profiles, str):
        stripped = lamp_profiles.strip()
        if stripped:
            try:
                parsed_lamp_profiles = json.loads(stripped)
            except (ValueError, TypeError):
                parsed_lamp_profiles = lamp_profiles
        else:
            parsed_lamp_profiles = None

    return {
        "id": extract_entity_id(entity),
        "entity_type": entity_type,
        "name": extract_entity_name(entity),
        "lamp_profiles": parsed_lamp_profiles,
        "raw_keys": sorted(list(entity.keys()))
    }


# ============================================================
# ROOT
# ============================================================

@app.get("/", include_in_schema=False)
def read_root():
    """Serve the Flutter Web application at the main Render URL."""
    frontend_index = BASE_DIR.parent / "frontend" / "index.html"

    if frontend_index.is_file():
        return FileResponse(str(frontend_index))

    # Keep a useful diagnostic response if the Flutter build was not deployed.
    email, password = get_schnell_iot_credentials()
    return {
        "status": "online",
        "app": "BBMP Pending Poles Backend API",
        "message": "Flutter frontend files are missing",
        "expected_file": str(frontend_index),
        "master_poles_count": len(MASTER_POLES_DATA),
        "installed_records_count": len(INSTALLED_REPORT_DATA),
        "pending_poles_count": len(PENDING_POLES_DATA),
        "iot_credentials_configured": bool(email and password),
    }


# ============================================================
# REGIONS
# ============================================================

@app.get("/api/v1/regions")
def get_regions():

    # Regions are the two configured BBMP region assets directly under the
    # Bangalore (BBMP) ThingsBoard customer. Do not force the UI to wait for
    # the full live pending-pole calculation just to populate this dropdown.
    # The actual pole records and pending calculation remain live from
    # ThingsBoard in /api/v1/poles/filter.
    regions = [
        "BOMMANAHALLI",
        "EAST",
    ]

    return {
        "regions": regions,
        "source": "thingsboard_live_hierarchy"
    }


# ============================================================
# ZONES
# ============================================================

@app.get("/api/v1/zones")
def get_zones(
    region: Optional[str] = Query(
        None,
        description="Selected Region name"
    )
):
    """
    Return Region -> Zone directly from the ThingsBoard hierarchy.

    Do not scan the Pole Survey dataset here.  The hierarchy is represented
    by Contains relations, so this endpoint only asks ThingsBoard for the
    immediate children of the selected region.
    """
    if not region:
        return {
            "region": region,
            "zones": [],
            "source": "thingsboard_live_hierarchy"
        }

    normalized_region = _normalize_region(region)

    region_ids = {
        "EAST": EAST_ID,
        "BOMMANAHALLI": BOMMANAHALI_ID,
    }

    region_id = region_ids.get(normalized_region)

    if not region_id:
        return {
            "region": region,
            "zones": [],
            "source": "thingsboard_live_hierarchy"
        }

    token = schnell_iot_login()

    payload = {
        "entityFilter": {
            "type": "assetSearchQuery",
            "rootEntity": {
                "entityType": "ASSET",
                "id": region_id,
            },
            "direction": "FROM",
            "maxLevel": 1,
            "fetchLastLevelOnly": True,
            "relationType": "Contains",
            "assetTypes": [],
        },
        "entityFields": [
            {"type": "ENTITY_FIELD", "key": "name"},
            {"type": "ENTITY_FIELD", "key": "type"},
        ],
        "latestValues": [],
        "pageLink": {
            "pageSize": 100,
            "page": 0,
        },
    }

    try:
        response = requests.post(
            f"{TB_URL}/api/entitiesQuery/find",
            headers={
                "X-Authorization": f"Bearer {token}",
                "Content-Type": "application/json",
            },
            json=payload,
            timeout=30,
        )
    except requests.RequestException as exc:
        raise HTTPException(
            status_code=502,
            detail=f"ThingsBoard zone hierarchy query failed: {str(exc)}",
        )

    if response.status_code != 200:
        raise HTTPException(
            status_code=502,
            detail=(
                "ThingsBoard zone hierarchy query returned HTTP "
                f"{response.status_code}: {response.text[:500]}"
            ),
        )

    data = response.json()

    zones = []
    for entity in data.get("data", []):
        if not isinstance(entity, dict):
            continue

        name = extract_entity_name(entity)
        if name:
            zones.append(str(name).strip())

    zones = sorted(set(zones))

    return {
        "region": region,
        "zones": zones,
        "source": "thingsboard_live_hierarchy",
    }


# ============================================================
# WARDS
# ============================================================

@app.get("/api/v1/wards")
def get_wards(
    region: Optional[str] = Query(
        None,
        description="Selected Region name"
    ),
    zone: str = Query(
        ...,
        description="Selected Zone name"
    )
):
    """
    Return Region -> Zone -> Ward directly from the ThingsBoard hierarchy.

    This endpoint deliberately does NOT call _get_live_pending_records(),
    because that would fetch the complete Pole Survey + Lamp Installation
    datasets just to populate the Ward dropdown.
    """
    if not region or not zone:
        return {
            "region": region,
            "zone": zone,
            "wards": [],
            "source": "thingsboard_live_hierarchy",
        }

    normalized_region = _normalize_region(region)

    region_ids = {
        "EAST": EAST_ID,
        "BOMMANAHALLI": BOMMANAHALI_ID,
    }

    region_id = region_ids.get(normalized_region)

    if not region_id:
        return {
            "region": region,
            "zone": zone,
            "wards": [],
            "source": "thingsboard_live_hierarchy",
        }

    token = schnell_iot_login()

    # First find the selected zone as a direct child of the region.
    region_payload = {
        "entityFilter": {
            "type": "assetSearchQuery",
            "rootEntity": {
                "entityType": "ASSET",
                "id": region_id,
            },
            "direction": "FROM",
            "maxLevel": 1,
            "fetchLastLevelOnly": True,
            "relationType": "Contains",
            "assetTypes": [],
        },
        "entityFields": [
            {"type": "ENTITY_FIELD", "key": "name"},
            {"type": "ENTITY_FIELD", "key": "type"},
        ],
        "latestValues": [],
        "pageLink": {
            "pageSize": 100,
            "page": 0,
        },
    }

    try:
        response = requests.post(
            f"{TB_URL}/api/entitiesQuery/find",
            headers={
                "X-Authorization": f"Bearer {token}",
                "Content-Type": "application/json",
            },
            json=region_payload,
            timeout=30,
        )
    except requests.RequestException as exc:
        raise HTTPException(
            status_code=502,
            detail=f"ThingsBoard region hierarchy query failed: {str(exc)}",
        )

    if response.status_code != 200:
        raise HTTPException(
            status_code=502,
            detail=(
                "ThingsBoard region hierarchy query returned HTTP "
                f"{response.status_code}: {response.text[:500]}"
            ),
        )

    zone_id = None

    for entity in response.json().get("data", []):
        if not isinstance(entity, dict):
            continue

        name = extract_entity_name(entity)

        if name and str(name).strip().casefold() == zone.strip().casefold():
            entity_id = entity.get("entityId")

            if isinstance(entity_id, dict):
                zone_id = entity_id.get("id")
            elif isinstance(entity_id, str):
                zone_id = entity_id

            break

    if not zone_id:
        return {
            "region": region,
            "zone": zone,
            "wards": [],
            "source": "thingsboard_live_hierarchy",
        }

    # Then find the selected zone's direct Contains children (the wards).
    zone_payload = {
        "entityFilter": {
            "type": "assetSearchQuery",
            "rootEntity": {
                "entityType": "ASSET",
                "id": str(zone_id),
            },
            "direction": "FROM",
            "maxLevel": 1,
            "fetchLastLevelOnly": True,
            "relationType": "Contains",
            "assetTypes": [],
        },
        "entityFields": [
            {"type": "ENTITY_FIELD", "key": "name"},
            {"type": "ENTITY_FIELD", "key": "type"},
        ],
        "latestValues": [],
        "pageLink": {
            "pageSize": 100,
            "page": 0,
        },
    }

    try:
        response = requests.post(
            f"{TB_URL}/api/entitiesQuery/find",
            headers={
                "X-Authorization": f"Bearer {token}",
                "Content-Type": "application/json",
            },
            json=zone_payload,
            timeout=30,
        )
    except requests.RequestException as exc:
        raise HTTPException(
            status_code=502,
            detail=f"ThingsBoard zone hierarchy query failed: {str(exc)}",
        )

    if response.status_code != 200:
        raise HTTPException(
            status_code=502,
            detail=(
                "ThingsBoard zone hierarchy query returned HTTP "
                f"{response.status_code}: {response.text[:500]}"
            ),
        )

    wards = []
    for entity in response.json().get("data", []):
        if not isinstance(entity, dict):
            continue

        name = extract_entity_name(entity)
        if name:
            wards.append(str(name).strip())

    wards = sorted(set(wards))

    return {
        "region": region,
        "zone": zone,
        "wards": wards,
        "source": "thingsboard_live_hierarchy",
    }


# ============================================================
# POLE WITH OLD LAMP OPTIONS
# ============================================================

@app.get(
    "/api/v1/pole-with-old-lamp-options"
)
def get_pole_old_lamp_options():

    return {
        "options": [
            "LED",
            "Non-LED",
            "Empty"
        ]
    }


# ============================================================
# WARD HIERARCHY DIAGNOSTIC (TEMPORARY)
# ============================================================

@app.get("/api/v1/wards-debug")
def wards_debug(
    region: str = Query(...),
    zone: str = Query(...),
):
    """Temporary diagnostic endpoint: expose the raw Region -> Zone -> child hierarchy."""
    normalized_region = _normalize_region(region)
    region_ids = {
        "EAST": EAST_ID,
        "BOMMANAHALLI": BOMMANAHALI_ID,
    }
    region_id = region_ids.get(normalized_region)
    if not region_id:
        return {"error": "Unknown region", "region": region, "zone": zone}

    token = schnell_iot_login()
    headers = {
        "X-Authorization": f"Bearer {token}",
        "Content-Type": "application/json",
    }

    def hierarchy_payload(root_id: str, root_type: str = "ASSET"):
        return {
            "entityFilter": {
                "type": "assetSearchQuery",
                "rootEntity": {"entityType": root_type, "id": root_id},
                "direction": "FROM",
                "maxLevel": 1,
                "fetchLastLevelOnly": True,
                "relationType": "Contains",
                "assetTypes": [],
            },
            "entityFields": [
                {"type": "ENTITY_FIELD", "key": "name"},
                {"type": "ENTITY_FIELD", "key": "type"},
            ],
            "latestValues": [],
            "pageLink": {"pageSize": 100, "page": 0},
        }

    def do_query(root_id: str, root_type: str = "ASSET"):
        r = requests.post(
            f"{TB_URL}/api/entitiesQuery/find",
            headers=headers,
            json=hierarchy_payload(root_id, root_type),
            timeout=30,
        )
        return r.status_code, r.json() if r.status_code == 200 else {"raw": r.text[:1000]}

    region_status, region_body = do_query(region_id)
    region_entities = region_body.get("data", []) if isinstance(region_body, dict) else []

    matched_zone = None
    for entity in region_entities:
        if not isinstance(entity, dict):
            continue
        name = extract_entity_name(entity)
        if name and str(name).strip().casefold() == zone.strip().casefold():
            matched_zone = entity
            break

    if not matched_zone:
        return {
            "region": region,
            "zone": zone,
            "region_query_status": region_status,
            "region_child_count": len(region_entities),
            "region_children": region_entities,
            "matched_zone": None,
        }

    zone_id = matched_zone.get("id")
    if isinstance(zone_id, dict):
        zone_id = zone_id.get("id")
    zone_type = matched_zone.get("type") or "ASSET"

    child_status, child_body = do_query(str(zone_id), "ASSET")
    child_entities = child_body.get("data", []) if isinstance(child_body, dict) else []

    return {
        "region": region,
        "zone": zone,
        "region_query_status": region_status,
        "matched_zone": matched_zone,
        "zone_id": zone_id,
        "zone_reported_type": zone_type,
        "zone_child_query_status": child_status,
        "zone_child_count": len(child_entities),
        "zone_children": child_entities,
    }


# ============================================================
# LAMP TYPES
# ============================================================


@app.get("/api/v1/lamp-types")
def get_lamp_types(
    region: Optional[str] = Query(None, description="Selected Region name"),
    zone: Optional[str] = Query(None, description="Selected Zone name"),
    ward: Optional[str] = Query(None, description="Selected Ward name"),
    pole_old_lamp: str = Query(..., description="Selected Pole With Old Lamp classification"),
):
    """Return live Lamp Type values available for the selected filters."""
    pol_cls = str(pole_old_lamp or "").strip()
    if pol_cls not in {"LED", "Non-LED", "Empty"}:
        raise HTTPException(
            status_code=400,
            detail="Invalid Pole With Old Lamp classification",
        )

    # Use exactly the same live pending dataset as /poles/filter.
    records = _get_live_pending_records().copy()

    if region:
        wanted_region = _normalize_filter_text(_normalize_region(region))
        records = [
            p for p in records
            if _normalize_filter_text(p.get("region")) == wanted_region
        ]

    if zone:
        wanted_zone = _normalize_filter_text(zone)
        records = [
            p for p in records
            if _normalize_filter_text(p.get("zone")) == wanted_zone
        ]

    if ward:
        wanted_ward = _normalize_filter_text(ward)
        records = [
            p for p in records
            if _normalize_filter_text(p.get("ward")) == wanted_ward
        ]

    records = [p for p in records if _matches_pole_old_lamp(p, pol_cls)]

    lamp_types = sorted({
        _canonical_lamp_type(p.get("lamp_type"))
        for p in records
        if _canonical_lamp_type(p.get("lamp_type"))
    })

    if pol_cls == "Empty":
        lamp_types = ["-"] if records else []

    return {
        "region": region,
        "zone": zone,
        "ward": ward,
        "pole_old_lamp": pol_cls,
        "lamp_types": lamp_types,
        "count": len(records),
    }


# ============================================================
# FILTER POLES
# ============================================================

LIVE_PENDING_CACHE: Optional[List[Dict[str, Any]]] = None
LIVE_PENDING_CACHE_TIME: float = 0.0
LIVE_PENDING_CACHE_TTL_SECONDS = 300
LIVE_PENDING_CACHE_LOCK = Lock()


def _build_live_pending_records(token: str) -> List[Dict[str, Any]]:
    """Build a complete live pending dataset without mutating the cache."""
    survey_records = _fetch_all_bangalore_pole_survey_records(token)
    installed_records = _fetch_all_bangalore_installed_records(token)

    installed_poles = {
        _normalize_pole_number(record.get("pole_id"))
        for record in installed_records
        if _normalize_pole_number(record.get("pole_id"))
    }

    pending_poles: List[Dict[str, Any]] = []
    for pole in survey_records:
        pole_number = _normalize_pole_number(pole.get("pole_number"))
        if not pole_number or pole_number in installed_poles:
            continue

        pole_old_lamp, lamp_type = _classify_live_pole_lamp(
            pole.get("lamp_profiles")
        )
        record = dict(pole)
        record["pole_number"] = pole_number
        record["region"] = _normalize_region(record.get("region"))
        record["zone"] = str(record.get("zone") or "").strip()
        record["ward"] = str(record.get("ward") or "").strip()
        record["pole_old_lamp"] = pole_old_lamp
        record["lamp_type"] = lamp_type
        pending_poles.append(record)

    return pending_poles


def _get_live_pending_records(force_refresh: bool = False) -> List[Dict[str, Any]]:
    """Return live pending poles with a thread-safe, transactional 5-minute cache.

    A refresh is built completely before replacing the current cache. If a later
    refresh fails, an existing valid cache is retained instead of being replaced
    by an empty/partial dataset. This prevents repeated filter attempts from
    corrupting the data shown by the application.
    """
    global LIVE_PENDING_CACHE, LIVE_PENDING_CACHE_TIME

    now = time.time()
    if (
        not force_refresh
        and LIVE_PENDING_CACHE is not None
        and (now - LIVE_PENDING_CACHE_TIME) < LIVE_PENDING_CACHE_TTL_SECONDS
    ):
        return LIVE_PENDING_CACHE

    # Only one request may refresh the expensive live dataset at a time.
    with LIVE_PENDING_CACHE_LOCK:
        now = time.time()
        if (
            not force_refresh
            and LIVE_PENDING_CACHE is not None
            and (now - LIVE_PENDING_CACHE_TIME) < LIVE_PENDING_CACHE_TTL_SECONDS
        ):
            return LIVE_PENDING_CACHE

        previous_cache = LIVE_PENDING_CACHE
        previous_cache_time = LIVE_PENDING_CACHE_TIME

        try:
            token = schnell_iot_login()
            refreshed = _build_live_pending_records(token)
            refreshed_time = time.time()

            # Replace the cache only after BOTH live datasets were fetched and
            # the complete pending list was successfully constructed.
            LIVE_PENDING_CACHE = refreshed
            LIVE_PENDING_CACHE_TIME = refreshed_time
            return refreshed
        except Exception as exc:
            # Never destroy a previously valid cache because an upstream request
            # temporarily failed. Initial load still raises the real error.
            if previous_cache is not None:
                LIVE_PENDING_CACHE = previous_cache
                LIVE_PENDING_CACHE_TIME = previous_cache_time
                return previous_cache
            if PENDING_POLES_DATA:
                print(f"[LIVE REFRESH WARNING] Upstream live fetch failed ({exc}). Using precomputed fallback.", file=sys.stderr)
                return PENDING_POLES_DATA
            raise


def _normalize_filter_lamp_type(value: Optional[str]) -> Optional[str]:
    """Normalize UI lamp-type aliases to canonical live-record labels."""
    if value is None:
        return None
    raw = str(value).strip()
    if not raw:
        return None
    return _canonical_lamp_type(raw)


def _normalize_filter_text(value: Any) -> str:
    """Normalize hierarchy/filter text without changing displayed values."""
    return str(value or "").strip().casefold()


def _matches_pole_old_lamp(
    pole: Dict[str, Any],
    selected: Optional[str],
) -> bool:
    if not selected:
        return True
    return _normalize_filter_text(pole.get("pole_old_lamp")) == _normalize_filter_text(selected)


def _matches_lamp_type(
    pole: Dict[str, Any],
    selected: Optional[str],
) -> bool:
    if not selected:
        return True
    wanted = _normalize_filter_lamp_type(selected)
    actual = _normalize_filter_lamp_type(pole.get("lamp_type"))
    return _normalize_filter_text(actual) == _normalize_filter_text(wanted)


@app.post("/api/v1/poles/filter")
def filter_poles(
    req: FilterRequest
):

    # Production path: use live ThingsBoard data. Do not silently fall back
    # to the old sample dataset if the live service is unavailable.
    results = _get_live_pending_records().copy()

    if req.region:
        wanted_region = _normalize_filter_text(_normalize_region(req.region))
        results = [
            p for p in results
            if _normalize_filter_text(p.get("region")) == wanted_region
        ]

    if req.zone:
        wanted_zone = _normalize_filter_text(req.zone)
        results = [
            p for p in results
            if _normalize_filter_text(p.get("zone")) == wanted_zone
        ]

    if req.ward:
        wanted_ward = _normalize_filter_text(req.ward)
        results = [
            p for p in results
            if _normalize_filter_text(p.get("ward")) == wanted_ward
        ]

    if req.pole_old_lamp:
        results = [
            p
            for p in results
            if _matches_pole_old_lamp(
                p,
                req.pole_old_lamp,
            )
        ]

    if req.lamp_type:
        results = [
            p
            for p in results
            if _matches_lamp_type(
                p,
                req.lamp_type,
            )
        ]

    # Keep Starting Pole ordering deterministic between repeated identical requests.
    results.sort(key=lambda p: _normalize_pole_number(p.get("pole_number")))

    return {
        "count": len(results),
        "poles": results
    }


# ============================================================
# DISTANCE CALCULATION
# ============================================================

@app.post(
    "/api/v1/poles/calculate-distance"
)
def calculate_distance(
    req: DistanceRequest
):

    # Production path: use the live pending-pole cache.
    filtered = _get_live_pending_records().copy()

    if req.region:
        wanted_region = _normalize_filter_text(_normalize_region(req.region))
        filtered = [
            p for p in filtered
            if _normalize_filter_text(p.get("region")) == wanted_region
        ]

    if req.zone:
        wanted_zone = _normalize_filter_text(req.zone)
        filtered = [
            p for p in filtered
            if _normalize_filter_text(p.get("zone")) == wanted_zone
        ]

    if req.ward:
        wanted_ward = _normalize_filter_text(req.ward)
        filtered = [
            p for p in filtered
            if _normalize_filter_text(p.get("ward")) == wanted_ward
        ]

    if req.pole_old_lamp:
        filtered = [
            p
            for p in filtered
            if _matches_pole_old_lamp(
                p,
                req.pole_old_lamp,
            )
        ]

    if req.lamp_type:
        filtered = [
            p
            for p in filtered
            if _matches_lamp_type(
                p,
                req.lamp_type,
            )
        ]

    if req.filtered_pole_ids:

        filtered = [
            p
            for p in filtered
            if p["id"] in req.filtered_pole_ids
        ]

    requested_start = _normalize_pole_number(req.starting_pole_number)
    start_pole = next(
        (
            p for p in filtered
            if _normalize_pole_number(p.get("pole_number")) == requested_start
        ),
        None,
    )

    if not start_pole:

        start_pole = next(
            (
                p
                for p in _get_live_pending_records()
                if _normalize_pole_number(p.get("pole_number")) == requested_start
            ),
            None
        )

    if not start_pole:

        raise HTTPException(
            status_code=404,
            detail=(
                f"Starting Pole "
                f"{req.starting_pole_number} "
                "not found."
            )
        )

    start_lat = start_pole["latitude"]
    start_lon = start_pole["longitude"]

    calculated = []

    for pole in filtered:

        p_lat = pole["latitude"]
        p_lon = pole["longitude"]

        dist_m = haversine_distance(
            float(start_lat),
            float(start_lon),
            float(p_lat),
            float(p_lon),
        )

        pole_copy = pole.copy()

        pole_copy["distance_meters"] = (
            dist_m
        )

        pole_copy["distance_formatted"] = (
            format_distance(dist_m)
        )

        pole_copy["google_maps_url"] = (
            "https://www.google.com/maps/search/"
            f"?api=1&query={p_lat},{p_lon}"
        )

        calculated.append(
            pole_copy
        )

    calculated.sort(
        key=lambda x: x["distance_meters"]
    )

    for index, p in enumerate(
        calculated,
        1
    ):

        p["order"] = index

    return {
        "starting_pole": (
            req.starting_pole_number
        ),
        "count": len(calculated),
        "poles": calculated
    }


# ============================================================
# SCHNELL IOT TEST
# ============================================================

@app.get(
    "/api/v1/schnell-iot/test"
)
def test_schnell_iot():

    # Login inside the API process.
    # This fixes the Uvicorn reload problem.
    token = schnell_iot_login()

    raw_data = fetch_real_pole_assets(
        token,
        max_poles=5
    )

    entities = raw_data.get(
        "data",
        []
    )

    simplified_poles = [
        simplify_real_pole(entity)
        for entity in entities
        if isinstance(
            entity,
            dict
        )
    ]

    return {
        "status": "success",
        "source": (
            "Schnell IoT / ThingsBoard"
        ),
        "thingsboard_url": TB_URL,
        "root_entity": EAST_ID,
        "records_returned": len(
            simplified_poles
        ),
        "poles": simplified_poles,
        "raw_response_keys": (
            list(raw_data.keys())
            if isinstance(
                raw_data,
                dict
            )
            else []
        ),
    }


# ============================================================
# INSTALLED REPORT SYNC
# ============================================================

@app.post(
    "/api/v1/schnell-iot/sync-installed-report"
)
def sync_installed_report(
    payload: InstalledReportSyncRequest
):

    global INSTALLED_REPORT_DATA

    INSTALLED_REPORT_DATA = (
        payload.installed_pole_numbers
    )

    _recompute_pending()

    return {
        "status": "success",
        "installed_records_received": len(
            payload.installed_pole_numbers
        ),
        "pending_poles_remaining": len(
            PENDING_POLES_DATA
        )
    }


# ============================================================
# MASTER EXCEL UPLOAD
# ============================================================

@app.post(
    "/api/v1/upload-master-excel"
)
async def upload_master_excel(
    file: UploadFile = File(...)
):

    global MASTER_POLES_DATA

    temp_path = (
        f"temp_master_{file.filename}"
    )

    with open(
        temp_path,
        "wb"
    ) as buffer:

        shutil.copyfileobj(
            file.file,
            buffer
        )

    try:

        new_master = parse_excel_dataset(
            temp_path
        )

        MASTER_POLES_DATA = new_master

        _recompute_pending()

        if os.path.exists(temp_path):

            os.remove(
                temp_path
            )

        return {
            "status": "success",
            "message": (
                f"Successfully ingested "
                f"{len(new_master)} master poles "
                f"from {file.filename}"
            ),
            "master_poles_count": len(
                new_master
            ),
            "pending_poles_count": len(
                PENDING_POLES_DATA
            )
        }

    except Exception as e:

        if os.path.exists(temp_path):

            os.remove(
                temp_path
            )

        raise HTTPException(
            status_code=400,
            detail=(
                "Failed to parse Master Excel file: "
                f"{str(e)}"
            )
        )



# ============================================================
# SCHNELL IOT LAMP INSTALLATION TEST
# ============================================================

LIGHTPOINT_PAGE_SIZE = 1024
LIGHTPOINT_MAX_WORKERS = 16


def _tb_latest_attribute(entity: Dict[str, Any], key: str) -> Any:
    latest = entity.get("latest", {})
    if isinstance(latest, dict):
        attrs = latest.get("ATTRIBUTE", {})
        if isinstance(attrs, dict):
            value = attrs.get(key)
            if isinstance(value, dict):
                return value.get("value")
            return value
    return None


def _fetch_lightpoint_page(
    token: str,
    page: int,
    page_size: int = LIGHTPOINT_PAGE_SIZE,
) -> Dict[str, Any]:
    """Fetch one lightPoint page from ThingsBoard."""
    payload = {
        "entityFilter": {
            "type": "assetSearchQuery",
            "rootEntity": {
                "entityType": "CUSTOMER",
                "id": BANGALORE_ID,
            },
            "direction": "FROM",
            "maxLevel": 5,
            "fetchLastLevelOnly": False,
            "relationType": "Contains",
            "assetTypes": ["lightPoint"],
        },
        "entityFields": [
            {"type": "ENTITY_FIELD", "key": "name"}
        ],
        "latestValues": [
            {"type": "ATTRIBUTE", "key": "accuracy"},
            {"type": "ATTRIBUTE", "key": "ilm"},
            {"type": "ATTRIBUTE", "key": "installedBy"},
            {"type": "ATTRIBUTE", "key": "installedOn"},
            {"type": "ATTRIBUTE", "key": "lamp"},
            {"type": "ATTRIBUTE", "key": "lampWatts"},
            {"type": "ATTRIBUTE", "key": "landmark"},
            {"type": "ATTRIBUTE", "key": "latitude"},
            {"type": "ATTRIBUTE", "key": "longitude"},
            {"type": "ATTRIBUTE", "key": "poleId"},
            {"type": "ATTRIBUTE", "key": "region"},
            {"type": "ATTRIBUTE", "key": "state"},
            {"type": "ATTRIBUTE", "key": "wardName"},
            {"type": "ATTRIBUTE", "key": "zoneName"},
        ],
        "pageLink": {
            "pageSize": page_size,
            "page": page,
        },
    }

    response = requests.post(
        f"{TB_URL}/api/entitiesQuery/find",
        headers={
            "X-Authorization": f"Bearer {token}",
            "Content-Type": "application/json",
        },
        json=payload,
        timeout=60,
    )

    if response.status_code != 200:
        raise RuntimeError(
            f"ThingsBoard lightPoint page {page} returned HTTP "
            f"{response.status_code}: {response.text[:500]}"
        )

    data = response.json()
    if not isinstance(data, dict):
        raise RuntimeError("ThingsBoard returned an invalid lightPoint response.")

    return data


def _normalize_pole_number(value: Any) -> str:
    """Normalize a ThingsBoard pole number for matching and de-duplication."""
    if value is None:
        return ""
    return str(value).strip()


def _simplify_installed_lightpoint(entity: Dict[str, Any]) -> Optional[Dict[str, Any]]:
    pole_id = _tb_latest_attribute(entity, "poleId")
    state = _tb_latest_attribute(entity, "state")

    if pole_id is None:
        return None

    pole_id = _normalize_pole_number(pole_id)
    if not pole_id or str(state).strip().upper() != "INSTALLED":
        return None

    return {
        "pole_id": pole_id,
        "state": str(state).strip() if state is not None else "",
        "lamp": _tb_latest_attribute(entity, "lamp"),
        "lamp_watts": _tb_latest_attribute(entity, "lampWatts"),
        "installed_on": _tb_latest_attribute(entity, "installedOn"),
        "installed_by": _tb_latest_attribute(entity, "installedBy"),
        "region": _tb_latest_attribute(entity, "region"),
        "zone": _tb_latest_attribute(entity, "zoneName"),
        "ward": _tb_latest_attribute(entity, "wardName"),
        "latitude": _tb_latest_attribute(entity, "latitude"),
        "longitude": _tb_latest_attribute(entity, "longitude"),
        "landmark": _tb_latest_attribute(entity, "landmark"),
    }


def fetch_installed_lightpoints(
    token: str,
    page_size: int = LIGHTPOINT_PAGE_SIZE,
) -> Dict[str, Any]:
    """
    Fetch installed Lamp Installation records from ThingsBoard.

    The first page determines the total number of pages. Remaining pages
    are fetched concurrently with a small worker pool so the backend does
    not wait for 72 sequential network requests.
    """
    first_page = _fetch_lightpoint_page(token, 0, page_size)
    total_pages = int(first_page.get("totalPages", 1) or 1)
    total_elements = int(first_page.get("totalElements", 0) or 0)
    pages = {0: first_page}

    remaining_pages = list(range(1, total_pages))
    if remaining_pages:
        workers = min(LIGHTPOINT_MAX_WORKERS, len(remaining_pages))
        with ThreadPoolExecutor(max_workers=workers) as executor:
            futures = {
                executor.submit(
                    _fetch_lightpoint_page,
                    token,
                    page,
                    page_size,
                ): page
                for page in remaining_pages
            }
            for future in as_completed(futures):
                page = futures[future]
                pages[page] = future.result()

    installed_records = []
    seen_poles = set()

    for page in range(total_pages):
        data = pages.get(page, {})
        for entity in data.get("data", []):
            if not isinstance(entity, dict):
                continue
            record = _simplify_installed_lightpoint(entity)
            if record is None:
                continue
            pole_id = record["pole_id"]
            if pole_id in seen_poles:
                continue
            seen_poles.add(pole_id)
            installed_records.append(record)

    return {
        "status": "success",
        "source": "Schnell IoT / ThingsBoard",
        "asset_type": "lightPoint",
        "root_entity": BANGALORE_ID,
        "page_size": page_size,
        "total_lightpoint_entities": total_elements,
        "total_pages": total_pages,
        "pages_fetched": len(pages),
        "installed_records_count": len(installed_records),
        "sample_records": installed_records[:10],
        "sample_installed_poles": [
            record["pole_id"] for record in installed_records[:20]
        ],
    }


@app.get("/api/v1/schnell-iot/installed-poles-test")
def installed_poles_test():
    """Read-only performance test for live Lamp Installation data."""
    token = schnell_iot_login()
    return fetch_installed_lightpoints(token)



# ============================================================
# SCHNELL IOT POLE SURVEY TEST
# ============================================================
POLE_SURVEY_PAGE_SIZE = 1024
POLE_SURVEY_MAX_WORKERS = 16


def _fetch_pole_survey_page(
    token: str,
    page: int,
    page_size: int = POLE_SURVEY_PAGE_SIZE,
) -> Dict[str, Any]:
    """Fetch one live Pole Survey page from ThingsBoard."""
    payload = {
        "entityFilter": {
            "type": "assetSearchQuery",
            "rootEntity": {
                "entityType": "ASSET",
                "id": EAST_ID,
            },
            "direction": "FROM",
            "maxLevel": 5,
            "fetchLastLevelOnly": False,
            "relationType": "Contains",
            "assetTypes": ["pole"],
        },
        "entityFields": [
            {"type": "ENTITY_FIELD", "key": "name"},
            {"type": "ENTITY_FIELD", "key": "type"},
        ],
        "latestValues": [
            {"type": "ATTRIBUTE", "key": "region"},
            {"type": "ATTRIBUTE", "key": "zoneName"},
            {"type": "ATTRIBUTE", "key": "wardName"},
            {"type": "ATTRIBUTE", "key": "latitude"},
            {"type": "ATTRIBUTE", "key": "longitude"},
            {"type": "ATTRIBUTE", "key": "location"},
            {"type": "ATTRIBUTE", "key": "preciseLocation"},
            {"type": "ATTRIBUTE", "key": "lightDetails"},
            {"type": "ATTRIBUTE", "key": "lampProfiles"},
            {"type": "ATTRIBUTE", "key": "switchPointNo"},
            {"type": "ATTRIBUTE", "key": "type"},
            {"type": "ATTRIBUTE", "key": "condition"},
            {"type": "ATTRIBUTE", "key": "height"},
            {"type": "ATTRIBUTE", "key": "span"},
            {"type": "ATTRIBUTE", "key": "installedBy"},
            {"type": "ATTRIBUTE", "key": "installedOn"},
            {"type": "ATTRIBUTE", "key": "remarks"},
            {"type": "ATTRIBUTE", "key": "armCount"},
        ],
        "pageLink": {
            "pageSize": page_size,
            "page": page,
        },
    }

    response = requests.post(
        f"{TB_URL}/api/entitiesQuery/find",
        headers={
            "X-Authorization": f"Bearer {token}",
            "Content-Type": "application/json",
        },
        json=payload,
        timeout=60,
    )

    if response.status_code != 200:
        raise RuntimeError(
            f"ThingsBoard Pole Survey page {page} returned HTTP "
            f"{response.status_code}: {response.text[:500]}"
        )

    data = response.json()
    if not isinstance(data, dict):
        raise RuntimeError("ThingsBoard returned an invalid Pole Survey response.")

    return data


def _simplify_pole_survey(entity: Dict[str, Any]) -> Optional[Dict[str, Any]]:
    """Convert one ThingsBoard Pole Survey entity to a compact record."""
    pole_number = extract_entity_name(entity)
    if not pole_number:
        return None

    return {
        "pole_number": _normalize_pole_number(pole_number),
        "entity_id": extract_entity_id(entity),
        "region": _tb_latest_attribute(entity, "region"),
        "zone": _tb_latest_attribute(entity, "zoneName"),
        "ward": _tb_latest_attribute(entity, "wardName"),
        "latitude": _tb_latest_attribute(entity, "latitude"),
        "longitude": _tb_latest_attribute(entity, "longitude"),
        "location": _tb_latest_attribute(entity, "location"),
        "precise_location": _tb_latest_attribute(entity, "preciseLocation"),
        "light_details": _tb_latest_attribute(entity, "lightDetails"),
        "lamp_profiles": _tb_latest_attribute(entity, "lampProfiles"),
        "switch_point_no": _tb_latest_attribute(entity, "switchPointNo"),
        "type": _tb_latest_attribute(entity, "type"),
        "condition": _tb_latest_attribute(entity, "condition"),
        "height": _tb_latest_attribute(entity, "height"),
        "span": _tb_latest_attribute(entity, "span"),
        "installed_by": _tb_latest_attribute(entity, "installedBy"),
        "installed_on": _tb_latest_attribute(entity, "installedOn"),
        "remarks": _tb_latest_attribute(entity, "remarks"),
        "arm_count": _tb_latest_attribute(entity, "armCount"),
    }


def fetch_pole_survey(
    token: str,
    page_size: int = POLE_SURVEY_PAGE_SIZE,
) -> Dict[str, Any]:
    """
    Fetch the complete live Pole Survey dataset from ThingsBoard.

    The first page determines the number of pages. Remaining pages are
    fetched concurrently to avoid 87 sequential network requests.
    """
    first_page = _fetch_pole_survey_page(token, 0, page_size)
    total_pages = int(first_page.get("totalPages", 1) or 1)
    total_elements = int(first_page.get("totalElements", 0) or 0)
    pages = {0: first_page}

    remaining_pages = list(range(1, total_pages))
    if remaining_pages:
        workers = min(POLE_SURVEY_MAX_WORKERS, len(remaining_pages))
        with ThreadPoolExecutor(max_workers=workers) as executor:
            futures = {
                executor.submit(
                    _fetch_pole_survey_page,
                    token,
                    page,
                    page_size,
                ): page
                for page in remaining_pages
            }
            for future in as_completed(futures):
                page = futures[future]
                pages[page] = future.result()

    poles = []
    seen_poles = set()

    for page in range(total_pages):
        data = pages.get(page, {})
        for entity in data.get("data", []):
            if not isinstance(entity, dict):
                continue
            pole = _simplify_pole_survey(entity)
            if pole is None:
                continue
            pole_number = pole["pole_number"]
            if not pole_number or pole_number in seen_poles:
                continue
            seen_poles.add(pole_number)
            poles.append(pole)

    return {
        "status": "success",
        "source": "Schnell IoT / ThingsBoard",
        "asset_type": "pole",
        "root_entity": EAST_ID,
        "page_size": page_size,
        "total_pole_entities": total_elements,
        "total_pages": total_pages,
        "pages_fetched": len(pages),
        "unique_poles": len(poles),
        "sample_poles": poles[:10],
    }




# ============================================================
# LIVE POLE SURVEY - BANGALORE CUSTOMER TEST
# ============================================================


def fetch_pole_survey_bangalore(token: str) -> Dict[str, Any]:
    """Fetch pole assets from the Bangalore (BBMP) customer root.

    This is a read-only validation endpoint. It is intentionally separate
    from the existing EAST-rooted Pole Survey test until the full BBMP
    dataset is verified.
    """
    url = f"{TB_URL}/api/entitiesQuery/find"
    headers = {
        "X-Authorization": f"Bearer {token}",
        "Content-Type": "application/json",
    }

    latest_keys = [
        "region",
        "zoneName",
        "wardName",
        "latitude",
        "longitude",
        "location",
        "preciseLocation",
        "lightDetails",
        "lampProfiles",
        "switchPointNo",
        "type",
        "condition",
        "height",
        "span",
        "installedBy",
        "installedOn",
        "remarks",
        "armCount",
    ]

    def build_payload(page: int) -> Dict[str, Any]:
        return {
            "entityFilter": {
                "type": "assetSearchQuery",
                "rootEntity": {
                    "entityType": "CUSTOMER",
                    "id": BANGALORE_ID,
                },
                "direction": "FROM",
                "maxLevel": 5,
                "fetchLastLevelOnly": False,
                "relationType": "Contains",
                "assetTypes": ["pole"],
            },
            "entityFields": [
                {"type": "ENTITY_FIELD", "key": "name"},
                {"type": "ENTITY_FIELD", "key": "type"},
            ],
            "latestValues": [
                {"type": "ATTRIBUTE", "key": key}
                for key in latest_keys
            ],
            "pageLink": {
                "pageSize": POLE_SURVEY_PAGE_SIZE,
                "page": page,
            },
        }

    def request_page(page: int) -> Dict[str, Any]:
        try:
            response = requests.post(
                url,
                headers=headers,
                json=build_payload(page),
                timeout=60,
            )
        except requests.RequestException as exc:
            raise HTTPException(
                status_code=502,
                detail=f"ThingsBoard Bangalore pole query failed: {str(exc)}",
            )

        if response.status_code != 200:
            raise HTTPException(
                status_code=502,
                detail=(
                    "ThingsBoard Bangalore pole query returned HTTP "
                    f"{response.status_code}: {response.text[:1000]}"
                ),
            )

        try:
            data = response.json()
        except ValueError:
            raise HTTPException(
                status_code=502,
                detail="ThingsBoard Bangalore pole query returned invalid JSON.",
            )

        return data if isinstance(data, dict) else {}

    first_page = request_page(0)
    first_entities = first_page.get("data", [])
    total_pages = int(first_page.get("totalPages") or 1)
    total_elements = int(first_page.get("totalElements") or len(first_entities))

    pages: Dict[int, List[Dict[str, Any]]] = {0: first_entities}
    remaining_pages = list(range(1, total_pages))

    if remaining_pages:
        max_workers = min(POLE_SURVEY_MAX_WORKERS, len(remaining_pages))
        with ThreadPoolExecutor(max_workers=max_workers) as executor:
            futures = {
                executor.submit(request_page, page): page
                for page in remaining_pages
            }
            for future in as_completed(futures):
                page = futures[future]
                pages[page] = future.result().get("data", [])

    records: List[Dict[str, Any]] = []
    seen: set[str] = set()

    for page in range(total_pages):
        for entity in pages.get(page, []):
            if not isinstance(entity, dict):
                continue
            record = _simplify_pole_survey(entity)
            pole_number = _normalize_pole_number(record.get("pole_number"))
            if not pole_number or pole_number in seen:
                continue
            seen.add(pole_number)
            records.append(record)

    region_counts: Dict[str, int] = {}
    for record in records:
        region = str(record.get("region") or "").strip() or "UNKNOWN"
        region_counts[region] = region_counts.get(region, 0) + 1

    return {
        "status": "success",
        "source": "Schnell IoT / ThingsBoard",
        "asset_type": "pole",
        "root_entity": BANGALORE_ID,
        "root_entity_type": "CUSTOMER",
        "page_size": POLE_SURVEY_PAGE_SIZE,
        "total_pole_entities": total_elements,
        "total_pages": total_pages,
        "pages_fetched": total_pages,
        "unique_poles": len(records),
        "region_counts": dict(sorted(region_counts.items())),
        "sample_poles": records[:10],
        "sample_pole_numbers": [record["pole_number"] for record in records[:20]],
    }


@app.get("/api/v1/schnell-iot/pole-survey-bangalore-test")
def test_bangalore_pole_survey():
    token = schnell_iot_login()
    return fetch_pole_survey_bangalore(token)


@app.get("/api/v1/schnell-iot/pole-survey-test")
def pole_survey_test():
    """Read-only test for the complete live Pole Survey dataset."""
    token = schnell_iot_login()
    return fetch_pole_survey(token)



def _fetch_all_bangalore_pole_survey_records(token: str) -> List[Dict[str, Any]]:
    """Fetch and return the complete Bangalore Pole Survey records."""
    first_page = _fetch_bangalore_pole_survey_page(token, 0, POLE_SURVEY_PAGE_SIZE)
    total_pages = int(first_page.get("totalPages") or 1)
    pages: Dict[int, Dict[str, Any]] = {0: first_page}
    remaining = list(range(1, total_pages))

    if remaining:
        workers = min(POLE_SURVEY_MAX_WORKERS, len(remaining))
        with ThreadPoolExecutor(max_workers=workers) as executor:
            futures = {
                executor.submit(
                    _fetch_bangalore_pole_survey_page,
                    token,
                    page,
                    POLE_SURVEY_PAGE_SIZE,
                ): page
                for page in remaining
            }
            for future in as_completed(futures):
                page = futures[future]
                pages[page] = future.result()

    records: List[Dict[str, Any]] = []
    seen: set[str] = set()
    for page in range(total_pages):
        for entity in pages.get(page, {}).get("data", []):
            if not isinstance(entity, dict):
                continue
            record = _simplify_pole_survey(entity)
            if not record:
                continue
            pole_number = _normalize_pole_number(record.get("pole_number"))
            if not pole_number or pole_number in seen:
                continue
            seen.add(pole_number)
            records.append(record)
    return records


def _fetch_bangalore_pole_survey_page(
    token: str,
    page: int,
    page_size: int = POLE_SURVEY_PAGE_SIZE,
) -> Dict[str, Any]:
    """Fetch one Bangalore Pole Survey page."""
    payload = {
        "entityFilter": {
            "type": "assetSearchQuery",
            "rootEntity": {"entityType": "CUSTOMER", "id": BANGALORE_ID},
            "direction": "FROM",
            "maxLevel": 5,
            "fetchLastLevelOnly": False,
            "relationType": "Contains",
            "assetTypes": ["pole"],
        },
        "entityFields": [
            {"type": "ENTITY_FIELD", "key": "name"},
            {"type": "ENTITY_FIELD", "key": "type"},
        ],
        "latestValues": [
            {"type": "ATTRIBUTE", "key": key}
            for key in [
                "region", "zoneName", "wardName", "latitude", "longitude",
                "location", "preciseLocation", "lightDetails", "lampProfiles",
                "switchPointNo", "type", "condition", "height", "span",
                "installedBy", "installedOn", "remarks", "armCount",
            ]
        ],
        "pageLink": {"pageSize": page_size, "page": page},
    }
    response = requests.post(
        f"{TB_URL}/api/entitiesQuery/find",
        headers={
            "X-Authorization": f"Bearer {token}",
            "Content-Type": "application/json",
        },
        json=payload,
        timeout=60,
    )
    if response.status_code != 200:
        raise HTTPException(
            status_code=502,
            detail=f"ThingsBoard Bangalore Pole Survey page {page} returned HTTP {response.status_code}: {response.text[:500]}",
        )
    data = response.json()
    if not isinstance(data, dict):
        raise HTTPException(status_code=502, detail="Invalid Pole Survey response from ThingsBoard.")
    return data


def _fetch_all_bangalore_installed_records(token: str) -> List[Dict[str, Any]]:
    """Fetch and return all unique installed lightPoint records."""
    first_page = _fetch_lightpoint_page(token, 0, LIGHTPOINT_PAGE_SIZE)
    total_pages = int(first_page.get("totalPages") or 1)
    pages: Dict[int, Dict[str, Any]] = {0: first_page}
    remaining = list(range(1, total_pages))

    if remaining:
        workers = min(LIGHTPOINT_MAX_WORKERS, len(remaining))
        with ThreadPoolExecutor(max_workers=workers) as executor:
            futures = {
                executor.submit(
                    _fetch_lightpoint_page,
                    token,
                    page,
                    LIGHTPOINT_PAGE_SIZE,
                ): page
                for page in remaining
            }
            for future in as_completed(futures):
                page = futures[future]
                pages[page] = future.result()

    records: List[Dict[str, Any]] = []
    seen: set[str] = set()
    for page in range(total_pages):
        for entity in pages.get(page, {}).get("data", []):
            if not isinstance(entity, dict):
                continue
            record = _simplify_installed_lightpoint(entity)
            if not record:
                continue
            pole_id = _normalize_pole_number(record.get("pole_id"))
            if not pole_id or pole_id in seen:
                continue
            seen.add(pole_id)
            records.append(record)
    return records


# ============================================================
# LIVE PENDING POLES - BANGALORE CUSTOMER TEST
# ============================================================

def _normalize_region(value: Any) -> str:
    """Normalize ThingsBoard region spelling for BBMP filters."""
    value = str(value or "").strip()
    compact = value.lower().replace(" ", "")
    if compact in {"bommanahali", "bommanahalli"}:
        return "BOMMANAHALLI"
    if compact == "east":
        return "EAST"
    return value.upper() if value else "UNKNOWN"


def _parse_lamp_profiles(value: Any) -> List[Dict[str, Any]]:
    """Parse Pole Survey lampProfiles from the different TB shapes we may receive."""
    if value is None:
        return []

    parsed = value
    if isinstance(value, str):
        stripped = value.strip()
        if not stripped:
            return []
        try:
            parsed = json.loads(stripped)
        except (TypeError, ValueError):
            return []

    # Normally lampProfiles is a JSON list. Accept one dict as a defensive
    # fallback because ThingsBoard attributes can occasionally be stored that way.
    if isinstance(parsed, dict):
        parsed = [parsed]

    if not isinstance(parsed, list):
        return []

    return [item for item in parsed if isinstance(item, dict)]


_EMPTY_LAMP_MARKERS = {
    "", "-", "BLANK", "NONE", "NULL", "NAN", "NA", "N/A", "EMPTY"
}


def _normalize_live_lamp_type(value: Any) -> str:
    """Normalize a lamp type for classification/filter matching."""
    return str(value or "").strip().upper().replace(" ", "")


def _canonical_lamp_type(value: Any) -> str:
    """Return the exact lamp-type labels used by the mobile application.

    Required LED-family labels are:
      LED
      FL LED
      LED,LED
      LED,FL LED
    """
    raw = str(value or "").strip()
    normalized = raw.upper().replace(" ", "")

    if normalized in _EMPTY_LAMP_MARKERS:
        return "-"

    # Known ThingsBoard representations for mixed LED/FL LED poles.
    if normalized in {"LED-FLED", "FLED-LED", "LED,FLLED", "FLLED,LED"}:
        return "LED,FL LED"
    if normalized in {"LED-LED", "LED,LED"}:
        return "LED,LED"
    if normalized in {"FLED", "FLLED", "FL-LED", "FL_LED"}:
        return "FL LED"
    if normalized == "LED":
        return "LED"

    # Handle comma-separated values defensively.
    parts = [part.strip() for part in raw.split(",") if part.strip()]
    if parts:
        canonical_parts = []
        for part in parts:
            part_norm = part.upper().replace(" ", "")
            if part_norm == "FLED" or part_norm == "FLLED":
                canonical_parts.append("FL LED")
            elif part_norm == "LED":
                canonical_parts.append("LED")
            else:
                canonical_parts.append(part.strip())
        return ",".join(canonical_parts)

    return raw


def _classify_live_pole_lamp(lamp_profiles: Any) -> tuple[str, str]:
    """Classify live Pole Survey lampProfiles into the application's groups."""
    profiles = _parse_lamp_profiles(lamp_profiles)

    lamp_types: List[str] = []
    for profile in profiles:
        raw_type = str(profile.get("type") or "").strip()
        normalized = _normalize_live_lamp_type(raw_type)
        if normalized in _EMPTY_LAMP_MARKERS:
            continue
        canonical = _canonical_lamp_type(raw_type)
        if canonical and canonical != "-":
            # Preserve repeated entries because LED + LED is a meaningful
            # lamp-type combination and must be displayed as "LED,LED".
            lamp_types.append(canonical)

    if not lamp_types:
        return "Empty", "-"

    normalized_types = {_normalize_live_lamp_type(t) for t in lamp_types}
    if normalized_types.issubset({"LED", "FLLED"}):
        return "LED", ",".join(lamp_types)

    return "Non-LED", ",".join(lamp_types)


@app.get("/api/v1/schnell-iot/live-pending-bangalore-test")
def live_pending_bangalore_test():
    """Refresh the live pending-pole cache and return a validation summary."""
    records = _get_live_pending_records(force_refresh=True)

    region_counts: Dict[str, int] = {}
    lamp_counts: Dict[str, int] = {}
    for pole in records:
        region = pole.get("region") or "UNKNOWN"
        region_counts[region] = region_counts.get(region, 0) + 1
        category = pole.get("pole_old_lamp") or "Empty"
        lamp_counts[category] = lamp_counts.get(category, 0) + 1

    return {
        "status": "success",
        "source": "Schnell IoT / ThingsBoard",
        "root_entity": BANGALORE_ID,
        "calculation": "Live Pole Survey - Live Lamp Installation",
        "pending_poles_total": len(records),
        "region_counts": dict(sorted(region_counts.items())),
        "pole_old_lamp_counts": dict(sorted(lamp_counts.items())),
        "sample_pending_poles": records[:20],
        "cache_ttl_seconds": LIVE_PENDING_CACHE_TTL_SECONDS,
    }


@app.post("/api/v1/schnell-iot/refresh-live-cache")
def refresh_live_cache():
    """Force-refresh live data so subsequent filter requests are local."""
    records = _get_live_pending_records(force_refresh=True)
    return {
        "status": "success",
        "pending_poles_total": len(records),
        "cache_ttl_seconds": LIVE_PENDING_CACHE_TTL_SECONDS,
    }

# ============================================================
# TECHNICIAN POLE IMAGES
# ============================================================

@app.post("/api/v1/poles/{pole_number}/images/{image_slot}")
async def upload_pole_image(
    pole_number: str,
    image_slot: int,
    file: UploadFile = File(...),
):
    """
    Save one technician image against an exact live pending pole.

    image_slot must be 1, 2, or 3.
    The backend validates the pole against the live pending dataset and
    stores the pole's live latitude/longitude in metadata.
    """
    if image_slot not in (1, 2, 3):
        raise HTTPException(
            status_code=400,
            detail="image_slot must be 1, 2, or 3.",
        )

    normalized_pole = _normalize_pole_number(pole_number)
    if not normalized_pole:
        raise HTTPException(
            status_code=400,
            detail="Pole number cannot be empty.",
        )

    live_pole = _find_live_pending_pole(normalized_pole)
    if not live_pole:
        raise HTTPException(
            status_code=404,
            detail=(
                f"Pole {normalized_pole} is not present in the current "
                "live pending-pole dataset."
            ),
        )

    try:
        latitude = float(live_pole.get("latitude"))
        longitude = float(live_pole.get("longitude"))
    except (TypeError, ValueError):
        raise HTTPException(
            status_code=422,
            detail=f"Pole {normalized_pole} does not have valid coordinates.",
        )

    original_name = Path(file.filename or "").name
    extension = Path(original_name).suffix.lower()

    if extension not in ALLOWED_IMAGE_EXTENSIONS:
        raise HTTPException(
            status_code=400,
            detail=(
                "Unsupported image type. Use JPG, JPEG, PNG, or WEBP."
            ),
        )

    content_type = (file.content_type or "").lower()

    # Android may send image files as application/octet-stream.
    # Trust the validated image extension instead of rejecting the upload
    # only because the multipart MIME type is generic.
    if not content_type.startswith("image/"):
        content_type_by_extension = {
            ".jpg": "image/jpeg",
            ".jpeg": "image/jpeg",
            ".png": "image/png",
            ".webp": "image/webp",
            ".gif": "image/gif",
        }

        content_type = content_type_by_extension.get(
            extension,
            "application/octet-stream",
        )

    # Read with a hard size limit.
    contents = await file.read(MAX_IMAGE_SIZE_BYTES + 1)

    if len(contents) > MAX_IMAGE_SIZE_BYTES:
        raise HTTPException(
            status_code=413,
            detail="Image is too large. Maximum allowed size is 10 MB.",
        )

    if not contents:
        raise HTTPException(
            status_code=400,
            detail="Uploaded image is empty.",
        )

    folder_name = _safe_pole_folder_name(normalized_pole)
    pole_folder = POLE_IMAGES_DIR / folder_name
    pole_folder.mkdir(parents=True, exist_ok=True)

    # Keep exactly one current file for each slot.
    for old_file in pole_folder.glob(f"image_{image_slot}.*"):
        try:
            old_file.unlink()
        except OSError:
            pass

    image_path = pole_folder / f"image_{image_slot}{extension}"
    image_path.write_bytes(contents)

    # Upload the same image to Google Drive and update only the matching
    # Image 1 / Image 2 / Image 3 cell in Google Sheets. Existing workflow
    # and local staging files are preserved.
    try:
        drive_url = _drive_upload_image(
            contents,
            image_path.name,
            content_type ,
            normalized_pole,
            image_slot,
        )
        _update_sheet_image_link(normalized_pole, image_slot, drive_url)
        google_drive_status = "uploaded"
    except Exception as exc:
        google_drive_status = "failed"
        raise HTTPException(
            status_code=502,
            detail=f"Image saved locally, but Google Drive/Sheets update failed: {exc}",
        )

    metadata = _read_image_metadata(pole_folder)
    images = metadata.get("images")
    if not isinstance(images, dict):
        images = {}

    uploaded_at = datetime.now(timezone.utc).isoformat()

    images[str(image_slot)] = {
        "filename": image_path.name,
        "latitude": latitude,
        "longitude": longitude,
        "uploaded_at": uploaded_at,
        "source": "technician_app",
        "google_drive_status": google_drive_status,
    }

    metadata.update(
        {
            "pole_number": normalized_pole,
            "latitude": latitude,
            "longitude": longitude,
            "region": live_pole.get("region"),
            "zone": live_pole.get("zone"),
            "ward": live_pole.get("ward"),
            "images": images,
        }
    )

    _write_image_metadata(pole_folder, metadata)

    return {
        "status": "success",
        "message": f"Image {image_slot} saved for {normalized_pole}.",
        "pole_number": normalized_pole,
        "latitude": latitude,
        "longitude": longitude,
        "image_slot": image_slot,
        "filename": image_path.name,
        "image_url": f"/pole-images/{folder_name}/{image_path.name}",
        "google_drive_status": google_drive_status,
    }


@app.get("/api/v1/poles/{pole_number}/images")
def get_pole_images(pole_number: str):
    """Return the three technician image slots saved for a pole."""
    normalized_pole = _normalize_pole_number(pole_number)

    if not normalized_pole:
        raise HTTPException(
            status_code=400,
            detail="Pole number cannot be empty.",
        )

    live_pole = _find_live_pending_pole(normalized_pole)
    if not live_pole:
        raise HTTPException(
            status_code=404,
            detail=f"Pole {normalized_pole} is not present in live pending poles.",
        )

    folder_name = _safe_pole_folder_name(normalized_pole)
    pole_folder = POLE_IMAGES_DIR / folder_name
    metadata = _read_image_metadata(pole_folder)
    stored_images = metadata.get("images", {})

    images = {}
    for slot in (1, 2, 3):
        item = stored_images.get(str(slot))
        if isinstance(item, dict):
            filename = item.get("filename")
            if filename:
                images[str(slot)] = {
                    **item,
                    "image_url": (
                        f"/pole-images/{folder_name}/{filename}"
                    ),
                }
            else:
                images[str(slot)] = None
        else:
            images[str(slot)] = None

    return {
        "status": "success",
        "pole_number": normalized_pole,
        "latitude": live_pole.get("latitude"),
        "longitude": live_pole.get("longitude"),
        "images": images,
        "google_drive_status": "connected",
    }


# ============================================================
# ============================================================
# FLUTTER WEB FRONTEND
# ============================================================
# The Flutter Web build is copied to ../frontend during deployment.
# API routes above remain available under /api/...
# The catch-all route below serves Flutter's index.html for browser
# routes and serves static files such as main.dart.js and assets.

FRONTEND_DIR = BASE_DIR.parent / "frontend"


@app.get("/{full_path:path}", include_in_schema=False)
def serve_flutter_frontend(full_path: str):
    """
    Serve the compiled Flutter Web application from the same Render URL.

    Examples:
      /                 -> frontend/index.html
      /main.dart.js     -> frontend/main.dart.js
      /assets/...       -> corresponding Flutter asset
      /some/flutter/route -> frontend/index.html
    """
    # Never let this frontend fallback handle API requests.
    if full_path == "api" or full_path.startswith("api/"):
        raise HTTPException(status_code=404, detail="API route not found")

    # Avoid exposing backend files or paths outside the frontend directory.
    requested_path = (FRONTEND_DIR / full_path).resolve()

    try:
        requested_path.relative_to(FRONTEND_DIR.resolve())
    except ValueError:
        raise HTTPException(status_code=404, detail="File not found")

    if requested_path.is_file():
        return FileResponse(str(requested_path))

    index_file = FRONTEND_DIR / "index.html"
    if index_file.is_file():
        return FileResponse(str(index_file))

@app.on_event("startup")
def startup_cache_warmup():
    import threading

    def _warmup_loop():
        try:
            print("[STARTUP] Pre-warming live pending pole cache from ThingsBoard...", file=sys.stderr)
            records = _get_live_pending_records(force_refresh=True)
            print(f"[STARTUP] Live pending pole cache ready with {len(records)} records.", file=sys.stderr)
        except Exception as exc:
            print(f"[STARTUP CACHE WARMUP ERROR] {exc}", file=sys.stderr)

        while True:
            time.sleep(240)
            try:
                _get_live_pending_records(force_refresh=True)
            except Exception as exc:
                print(f"[BACKGROUND CACHE REFRESH ERROR] {exc}", file=sys.stderr)

    thread = threading.Thread(target=_warmup_loop, daemon=True)
    thread.start()


# START SERVER
# ============================================================

if __name__ == "__main__":
    import uvicorn

    uvicorn.run(
        "main:app",
        host="0.0.0.0",
        port=int(os.getenv("PORT", "8000")),
        reload=os.getenv("UVICORN_RELOAD", "false").lower() == "true",
    )

