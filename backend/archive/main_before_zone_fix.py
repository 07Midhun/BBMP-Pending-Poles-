import os
import sys
import shutil
import json
import getpass
import time
import requests
from concurrent.futures import ThreadPoolExecutor, as_completed

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
    version="2.1.0"
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

TB_URL = "https://schnelliot.in"

EAST_ID = (
    "401219c0-45c4-11f0-94dc-77130b2f47e9"
)

BOMMANAHALI_ID = (
    "21456730-5bff-11f0-9e1d-abd300900bde"
)

BANGALORE_ID = (
    "e2119df0-45c3-11f0-94dc-77130b2f47e9"
)


# ============================================================
# TERMINAL CREDENTIAL INPUT
# ============================================================

def ask_schnell_iot_credentials():
    """
    Ask for Schnell IoT credentials in the terminal.

    The password is hidden while typing.

    The credentials are placed into the current process
    environment so that the Uvicorn reload process can inherit
    them.

    They are NOT written into this Python file.
    """

    print()
    print("=" * 55)
    print("        BBMP PENDING POLES BACKEND")
    print("=" * 55)
    print()
    print("Schnell IoT / ThingsBoard Login")
    print()

    email = input(
        "Schnell IoT Email: "
    ).strip()

    password = getpass.getpass(
        "Schnell IoT Password: "
    )

    if not email:
        print()
        print("ERROR: Email cannot be empty.")
        print()
        return False

    if not password:
        print()
        print("ERROR: Password cannot be empty.")
        print()
        return False

    # Store only in the current process environment.
    # Uvicorn's reload child process inherits these values.
    os.environ["SCHNELL_IOT_EMAIL"] = email
    os.environ["SCHNELL_IOT_PASSWORD"] = password

    print()

    return True


# ============================================================
# GET CURRENT CREDENTIALS
# ============================================================

def get_schnell_iot_credentials():
    email = os.environ.get(
        "SCHNELL_IOT_EMAIL",
        ""
    ).strip()

    password = os.environ.get(
        "SCHNELL_IOT_PASSWORD",
        ""
    )

    return email, password


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
            timeout=60
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

@app.get("/")
def read_root():

    email, password = (
        get_schnell_iot_credentials()
    )

    return {
        "status": "online",
        "app": "BBMP Pending Poles Backend API",
        "master_poles_count": len(
            MASTER_POLES_DATA
        ),
        "installed_records_count": len(
            INSTALLED_REPORT_DATA
        ),
        "pending_poles_count": len(
            PENDING_POLES_DATA
        ),
        "iot_credentials_configured": bool(
            email and password
        )
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

    # Zone hierarchy must not wait for the full pending calculation.
    # The pending calculation downloads both the complete Pole Survey and
    # complete Lamp Installation datasets, which is unnecessary here.
    # Fetch only the live Pole Survey hierarchy and derive Region -> Zone.
    token = schnell_iot_login()
    survey_records = _fetch_all_bangalore_pole_survey_records(token)

    if region:
        selected_region = _normalize_region(region)
        survey_records = [
            p
            for p in survey_records
            if _normalize_region(p.get("region")) == selected_region
        ]

    zones = sorted({
        str(p.get("zone")).strip()
        for p in survey_records
        if p.get("zone") and str(p.get("zone")).strip()
    })

    return {
        "region": region,
        "zones": zones,
        "source": "thingsboard_live_hierarchy"
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

    # Use the live pending cache so Region -> Zone -> Ward remains
    # consistent with the production pole list.
    filtered = _get_live_pending_records()

    if region:
        filtered = [
            p
            for p in filtered
            if p.get("region") == region
        ]

    filtered = [
        p
        for p in filtered
        if p.get("zone") == zone
    ]

    wards = sorted({
        p.get("ward")
        for p in filtered
        if p.get("ward")
    })

    return {
        "region": region,
        "zone": zone,
        "wards": wards,
        "source": "thingsboard_live"
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
# LAMP TYPES
# ============================================================

@app.get("/api/v1/lamp-types")
def get_lamp_types(
    pole_old_lamp: str = Query(
        ...,
        description=(
            "Selected Pole With Old Lamp "
            "classification"
        )
    )
):

    pol_cls = pole_old_lamp.strip()

    if pol_cls == "LED":

        return {
            "pole_old_lamp": "LED",
            "lamp_types": [
                "LED",
                "FLED",
                "LED-FLED",
                "LED-LED"
            ]
        }

    elif pol_cls == "Empty":

        return {
            "pole_old_lamp": "Empty",
            "lamp_types": [
                "-",
                "Blank"
            ]
        }

    elif pol_cls == "Non-LED":

        led_group = {
            "LED",
            "FLED",
            "LED-FLED",
            "LED,FLED",
            "LED-LED"
        }

        empty_group = {
            "-",
            "BLANK",
            "",
            "NONE",
            "NULL",
            "NAN"
        }

        all_types = {
            p["lamp_type"]
            for p in _get_live_pending_records()
            if p.get("lamp_type")
        }

        non_led_types = [
            t
            for t in all_types
            if t.upper() not in led_group
            and t.upper() not in empty_group
        ]

        if not non_led_types:

            non_led_types = [
                "CFL",
                "Sodium",
                "Halogen",
                "Tube"
            ]

        return {
            "pole_old_lamp": "Non-LED",
            "lamp_types": sorted(
                list(non_led_types)
            )
        }

    else:

        raise HTTPException(
            status_code=400,
            detail=(
                "Invalid Pole With Old Lamp "
                "classification"
            )
        )


# ============================================================
# FILTER POLES
# ============================================================

LIVE_PENDING_CACHE: Optional[List[Dict[str, Any]]] = None
LIVE_PENDING_CACHE_TIME: float = 0.0
LIVE_PENDING_CACHE_TTL_SECONDS = 300


def _get_live_pending_records(force_refresh: bool = False) -> List[Dict[str, Any]]:
    """Return live pending poles, refreshing the cache every 5 minutes."""
    global LIVE_PENDING_CACHE, LIVE_PENDING_CACHE_TIME

    now = time.time()
    if (
        not force_refresh
        and LIVE_PENDING_CACHE is not None
        and (now - LIVE_PENDING_CACHE_TIME) < LIVE_PENDING_CACHE_TTL_SECONDS
    ):
        return LIVE_PENDING_CACHE

    token = schnell_iot_login()
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
        record["region"] = _normalize_region(record.get("region"))
        record["pole_old_lamp"] = pole_old_lamp
        record["lamp_type"] = lamp_type
        pending_poles.append(record)

    LIVE_PENDING_CACHE = pending_poles
    LIVE_PENDING_CACHE_TIME = now
    return pending_poles


@app.post("/api/v1/poles/filter")
def filter_poles(
    req: FilterRequest
):

    # Production path: use live ThingsBoard data. Do not silently fall back
    # to the old sample dataset if the live service is unavailable.
    results = _get_live_pending_records().copy()

    if req.region:

        results = [
            p
            for p in results
            if p.get("region") == req.region
        ]

    if req.zone:

        results = [
            p
            for p in results
            if p.get("zone") == req.zone
        ]

    if req.ward:

        results = [
            p
            for p in results
            if p.get("ward") == req.ward
        ]

    if req.pole_old_lamp:

        results = [
            p
            for p in results
            if p.get("pole_old_lamp")
            == req.pole_old_lamp
        ]

    if req.lamp_type:

        results = [
            p
            for p in results
            if p.get("lamp_type")
            == req.lamp_type
        ]

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

        filtered = [
            p
            for p in filtered
            if p.get("region") == req.region
        ]

    if req.zone:

        filtered = [
            p
            for p in filtered
            if p.get("zone") == req.zone
        ]

    if req.ward:

        filtered = [
            p
            for p in filtered
            if p.get("ward") == req.ward
        ]

    if req.pole_old_lamp:

        filtered = [
            p
            for p in filtered
            if p.get("pole_old_lamp")
            == req.pole_old_lamp
        ]

    if req.lamp_type:

        filtered = [
            p
            for p in filtered
            if p.get("lamp_type")
            == req.lamp_type
        ]

    if req.filtered_pole_ids:

        filtered = [
            p
            for p in filtered
            if p["id"] in req.filtered_pole_ids
        ]

    start_pole = next(
        (
            p
            for p in filtered
            if p["pole_number"]
            == req.starting_pole_number
        ),
        None
    )

    if not start_pole:

        start_pole = next(
            (
                p
                for p in _get_live_pending_records()
                if p["pole_number"]
                == req.starting_pole_number
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
            start_lat,
            start_lon,
            p_lat,
            p_lon
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
LIGHTPOINT_MAX_WORKERS = 8


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
POLE_SURVEY_MAX_WORKERS = 8


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
    """Parse Pole Survey lampProfiles, which is stored as JSON text."""
    if value is None or value == "":
        return []

    parsed = value
    if isinstance(value, str):
        try:
            parsed = json.loads(value)
        except (TypeError, ValueError):
            return []

    if not isinstance(parsed, list):
        return []

    profiles: List[Dict[str, Any]] = []
    for item in parsed:
        if isinstance(item, dict):
            profiles.append(item)
    return profiles


def _classify_live_pole_lamp(lamp_profiles: Any) -> tuple[str, str]:
    """Return (Pole With Old Lamp, Lamp Type) using live Pole Survey data."""
    profiles = _parse_lamp_profiles(lamp_profiles)

    if not profiles:
        return "Empty", "-"

    lamp_types: List[str] = []
    for profile in profiles:
        lamp_type = str(profile.get("type") or "").strip()
        if lamp_type and lamp_type not in lamp_types:
            lamp_types.append(lamp_type)

    if not lamp_types:
        return "Empty", "-"

    normalized_types = {lamp_type.upper() for lamp_type in lamp_types}
    if normalized_types.issubset({"LED", "FLED"}):
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
# START SERVER
# ============================================================

if __name__ == "__main__":

    # Ask for credentials once.
    credentials_ok = (
        ask_schnell_iot_credentials()
    )

    if not credentials_ok:

        print(
            "Backend startup cancelled."
        )

        sys.exit(1)

    # Verify the credentials before starting API.
    print(
        "Connecting to Schnell IoT..."
    )

    try:

        test_token = schnell_iot_login()

        if test_token:

            print(
                "✓ Schnell IoT login successful."
            )

    except HTTPException as exc:

        print()
        print(
            "✗ Schnell IoT login failed."
        )

        print(
            f"Status: {exc.status_code}"
        )

        print(
            f"Reason: {exc.detail}"
        )

        print()

        sys.exit(1)

    print()
    print("=" * 55)
    print(
        "      Schnell IoT connection established"
    )
    print(
        "      BBMP Pending Poles backend ready"
    )
    print("=" * 55)
    print()

    import uvicorn

    uvicorn.run(
        "main:app",
        host="0.0.0.0",
        port=8000,
        reload=True
    )