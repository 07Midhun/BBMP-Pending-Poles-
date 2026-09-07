import os
import shutil
from typing import List, Optional, Dict, Any
from fastapi import FastAPI, UploadFile, File, Query, HTTPException, Body
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel

from excel_parser import (
    generate_sample_bbmp_data,
    parse_excel_dataset,
    haversine_distance,
    classify_old_lamp
)

app = FastAPI(
    title="BBMP Pending Poles API",
    description="Backend API for filtering BBMP pending poles, calculating geographical distance from a starting pole, and parsing Excel/IoT telemetry data.",
    version="1.0.0"
)

# Enable CORS for Flutter web / emulator access
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# In-memory store (or synced with PostGIS)
POLES_DATA: List[Dict[str, Any]] = generate_sample_bbmp_data()

class FilterRequest(BaseModel):
    zone: Optional[str] = None
    ward: Optional[str] = None
    pole_old_lamp: Optional[str] = None
    lamp_type: Optional[str] = None

class DistanceRequest(BaseModel):
    starting_pole_number: str
    filtered_pole_ids: Optional[List[int]] = None
    zone: Optional[str] = None
    ward: Optional[str] = None
    pole_old_lamp: Optional[str] = None
    lamp_type: Optional[str] = None

class IotTelemetryPayload(BaseModel):
    pole_number: str
    latitude: float
    longitude: float
    status: str
    lamp_type: Optional[str] = None

def format_distance(meters: float) -> str:
    if meters >= 1000.0:
        return f"{meters / 1000.0:.2f} km"
    return f"{int(round(meters))} m"

@app.get("/")
def read_root():
    return {
        "status": "online",
        "app": "BBMP Pending Poles Backend API",
        "total_poles_in_database": len(POLES_DATA)
    }

@app.get("/api/v1/zones")
def get_zones():
    """Returns list of distinct zones from source dataset."""
    zones = sorted(list({p["zone"] for p in POLES_DATA if p.get("zone")}))
    return {"zones": zones}

@app.get("/api/v1/wards")
def get_wards(zone: str = Query(..., description="Selected Zone name")):
    """Returns wards dependent on selected zone."""
    wards = sorted(list({p["ward"] for p in POLES_DATA if p.get("zone") == zone and p.get("ward")}))
    return {"zone": zone, "wards": wards}

@app.get("/api/v1/pole-with-old-lamp-options")
def get_pole_old_lamp_options():
    """Returns classification options: LED, Non-LED, Empty."""
    return {"options": ["LED", "Non-LED", "Empty"]}

@app.get("/api/v1/lamp-types")
def get_lamp_types(pole_old_lamp: str = Query(..., description="Selected Pole With Old Lamp classification")):
    """
    Returns dynamic lamp types based on selected Pole With Old Lamp.
    LED -> LED, FLED, LED-FLED, LED-LED
    Empty -> -, Blank
    Non-LED -> Excludes LED group and Empty group from available unique values
    """
    pol_cls = pole_old_lamp.strip()
    
    if pol_cls == "LED":
        return {"pole_old_lamp": "LED", "lamp_types": ["LED", "FLED", "LED-FLED", "LED-LED"]}
    elif pol_cls == "Empty":
        return {"pole_old_lamp": "Empty", "lamp_types": ["-", "Blank"]}
    elif pol_cls == "Non-LED":
        # All available lamp types in dataset excluding LED group and Empty group
        led_group = {"LED", "FLED", "LED-FLED", "LED-LED"}
        empty_group = {"-", "BLANK", "", "NONE", "NULL", "NAN"}
        
        all_types = {p["lamp_type"] for p in POLES_DATA if p.get("lamp_type")}
        non_led_types = [t for t in all_types if t.upper() not in led_group and t.upper() not in empty_group]
        
        # Default fallback if non-led dataset is empty
        if not non_led_types:
            non_led_types = ["CFL", "Sodium", "Halogen", "Tube"]
            
        return {"pole_old_lamp": "Non-LED", "lamp_types": sorted(list(non_led_types))}
    else:
        raise HTTPException(status_code=400, detail="Invalid Pole With Old Lamp classification")

@app.post("/api/v1/poles/filter")
def filter_poles(req: FilterRequest):
    """Filters dataset matching Zone AND Ward AND Lamp Classification AND Lamp Type."""
    results = POLES_DATA.copy()
    
    if req.zone:
        results = [p for p in results if p.get("zone") == req.zone]
    if req.ward:
        results = [p for p in results if p.get("ward") == req.ward]
    if req.pole_old_lamp:
        results = [p for p in results if p.get("pole_old_lamp") == req.pole_old_lamp]
    if req.lamp_type:
        results = [p for p in results if p.get("lamp_type") == req.lamp_type]
        
    return {
        "count": len(results),
        "poles": results
    }

@app.post("/api/v1/poles/calculate-distance")
def calculate_distance(req: DistanceRequest):
    """
    Core functional requirement:
    Calculates geographical distance from the selected Starting Pole to all matching poles
    using Latitude and Longitude (Haversine/PostGIS), and sorts nearest -> farthest.
    """
    filtered = POLES_DATA.copy()
    if req.zone:
        filtered = [p for p in filtered if p.get("zone") == req.zone]
    if req.ward:
        filtered = [p for p in filtered if p.get("ward") == req.ward]
    if req.pole_old_lamp:
        filtered = [p for p in filtered if p.get("pole_old_lamp") == req.pole_old_lamp]
    if req.lamp_type:
        filtered = [p for p in filtered if p.get("lamp_type") == req.lamp_type]
        
    if req.filtered_pole_ids:
        filtered = [p for p in filtered if p["id"] in req.filtered_pole_ids]
        
    # Find starting pole
    start_pole = next((p for p in filtered if p["pole_number"] == req.starting_pole_number), None)
    if not start_pole:
        # Fallback search in entire database
        start_pole = next((p for p in POLES_DATA if p["pole_number"] == req.starting_pole_number), None)
        
    if not start_pole:
        raise HTTPException(status_code=404, detail=f"Starting Pole {req.starting_pole_number} not found.")
        
    start_lat = start_pole["latitude"]
    start_lon = start_pole["longitude"]
    
    calculated = []
    for pole in filtered:
        p_lat = pole["latitude"]
        p_lon = pole["longitude"]
        dist_m = haversine_distance(start_lat, start_lon, p_lat, p_lon)
        
        pole_copy = pole.copy()
        pole_copy["distance_meters"] = dist_m
        pole_copy["distance_formatted"] = format_distance(dist_m)
        pole_copy["google_maps_url"] = f"https://www.google.com/maps/search/?api=1&query={p_lat},{p_lon}"
        calculated.append(pole_copy)
        
    # Sort ascending by distance (Nearest -> Farthest)
    calculated.sort(key=lambda x: x["distance_meters"])
    
    # Assign ordering index 1..N
    for index, p in enumerate(calculated, 1):
        p["order"] = index
        
    return {
        "starting_pole": req.starting_pole_number,
        "count": len(calculated),
        "poles": calculated
    }

@app.post("/api/v1/upload-excel")
async def upload_excel(file: UploadFile = File(...)):
    """Uploads and ingests an Excel or CSV file to replace current pole database."""
    global POLES_DATA
    
    temp_path = f"temp_{file.filename}"
    with open(temp_path, "wb") as buffer:
        shutil.copyfileobj(file.file, buffer)
        
    try:
        new_poles = parse_excel_dataset(temp_path)
        POLES_DATA = new_poles
        if os.path.exists(temp_path):
            os.remove(temp_path)
        return {
            "status": "success",
            "message": f"Successfully ingested {len(new_poles)} poles from {file.filename}",
            "count": len(new_poles)
        }
    except Exception as e:
        if os.path.exists(temp_path):
            os.remove(temp_path)
        raise HTTPException(status_code=400, detail=f"Failed to parse Excel file: {str(e)}")

@app.post("/api/v1/iot-telemetry")
def iot_telemetry_webhook(payload: IotTelemetryPayload):
    """Real-time IoT sensor telemetry endpoint for live pole updates."""
    global POLES_DATA
    existing = next((p for p in POLES_DATA if p["pole_number"] == payload.pole_number), None)
    if existing:
        existing["latitude"] = payload.latitude
        existing["longitude"] = payload.longitude
        if payload.lamp_type:
            existing["lamp_type"] = payload.lamp_type
            existing["pole_old_lamp"] = classify_old_lamp(payload.lamp_type)
        existing["status"] = payload.status
        return {"status": "updated", "pole": existing}
    else:
        new_pole = {
            "id": len(POLES_DATA) + 1,
            "pole_number": payload.pole_number,
            "zone": "IoT Zone",
            "ward": "IoT Ward",
            "pole_old_lamp": classify_old_lamp(payload.lamp_type or ""),
            "lamp_type": payload.lamp_type or "Unknown",
            "latitude": payload.latitude,
            "longitude": payload.longitude,
            "status": payload.status
        }
        POLES_DATA.append(new_pole)
        return {"status": "created", "pole": new_pole}

if __name__ == "__main__":
    import uvicorn
    uvicorn.run("main:app", host="0.0.0.0", port=8000, reload=True)
