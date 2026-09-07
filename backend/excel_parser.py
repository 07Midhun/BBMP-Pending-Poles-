import math
import os
import re
from typing import List, Dict, Any, Optional

try:
    import pandas as pd
except ImportError:
    pd = None

def haversine_distance(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    """
    Calculate the great circle distance between two points 
    on the earth (specified in decimal degrees) in meters.
    """
    R = 6371000.0  # Earth radius in meters
    
    phi1 = math.radians(lat1)
    phi2 = math.radians(lat2)
    delta_phi = math.radians(lat2 - lat1)
    delta_lambda = math.radians(lon2 - lon1)
    
    a = math.sin(delta_phi / 2.0) ** 2 + \
        math.cos(phi1) * math.cos(phi2) * math.sin(delta_lambda / 2.0) ** 2
    c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))
    
    return R * c

def classify_old_lamp(lamp_type_raw: str) -> str:
    """
    Classifies a raw lamp type into LED, Empty, or Non-LED.
    LED Group: LED, FLED, LED-FLED, LED-LED
    Empty Group: -, Blank, None, Empty, nan
    Non-LED Group: All other valid lamp types (e.g. CFL, Sodium, Halogen, Tube)
    """
    if lamp_type_raw is None or str(lamp_type_raw).strip() == "" or str(lamp_type_raw).lower() in ["nan", "null", "none", "blank"]:
        return "Empty"
    
    val = str(lamp_type_raw).strip().upper()
    if val in ["-", "HYPHEN", "BLANK"]:
        return "Empty"
    
    if val in ["LED", "FLED", "LED-FLED", "LED-LED"] or "LED" in val or "FLED" in val:
        return "LED"
    
    return "Non-LED"

def normalize_lamp_type(lamp_type_raw: str) -> str:
    """
    Normalizes raw lamp type string for UI presentation.
    """
    if lamp_type_raw is None or str(lamp_type_raw).strip() == "" or str(lamp_type_raw).lower() in ["nan", "null", "none"]:
        return "Blank"
    val = str(lamp_type_raw).strip()
    if val == "":
        return "Blank"
    return val

def generate_sample_bbmp_data() -> List[Dict[str, Any]]:
    """
    Generates realistic sample BBMP poles dataset for testing if no file is provided.
    """
    zones_wards = {
        "East": ["Ward 45", "Ward 46", "Ward 47", "Ward 48"],
        "West": ["Ward 60", "Ward 61", "Ward 62", "Ward 63"],
        "North": ["Ward 10", "Ward 11", "Ward 12"],
        "South": ["Ward 150", "Ward 151", "Ward 152"]
    }
    
    lamp_types = ["LED", "FLED", "LED-FLED", "LED-LED", "CFL", "Sodium", "Halogen", "Tube", "-", ""]
    
    data = []
    pole_id = 1
    
    # Coordinates centered around Bengaluru BBMP
    base_lats = {"East": 12.9820, "West": 12.9750, "North": 13.0200, "South": 12.9200}
    base_lons = {"East": 77.6730, "West": 77.5600, "North": 77.5900, "South": 77.5800}
    
    for zone, wards in zones_wards.items():
        base_lat = base_lats[zone]
        base_lon = base_lons[zone]
        
        for w_idx, ward in enumerate(wards):
            for i in range(1, 15):
                p_num = f"P{pole_id:04d}"
                raw_lamp = lamp_types[pole_id % len(lamp_types)]
                norm_lamp = normalize_lamp_type(raw_lamp)
                old_lamp_cls = classify_old_lamp(norm_lamp)
                
                # Small geographical offsets (approx 10-150m apart)
                lat = base_lat + (w_idx * 0.002) + (i * 0.00015) + ((i % 3) * 0.00008)
                lon = base_lon + (w_idx * 0.002) + (i * 0.00018) - ((i % 2) * 0.00005)
                
                data.append({
                    "id": pole_id,
                    "pole_number": p_num,
                    "zone": zone,
                    "ward": ward,
                    "pole_old_lamp": old_lamp_cls,
                    "lamp_type": norm_lamp,
                    "latitude": round(lat, 6),
                    "longitude": round(lon, 6)
                })
                pole_id += 1
                
    return data

def parse_excel_dataset(file_path: str) -> List[Dict[str, Any]]:
    """
    Parses an uploaded Excel (.xlsx, .xls) or CSV file.
    """
    if pd is None:
        raise RuntimeError("pandas library is required to parse Excel files.")
        
    ext = os.path.splitext(file_path)[1].lower()
    if ext in ['.xlsx', '.xls']:
        df = pd.read_excel(file_path)
    elif ext in ['.csv']:
        df = pd.read_csv(file_path)
    else:
        raise ValueError(f"Unsupported file format: {ext}")
        
    # Standardize column headers
    cols_map = {}
    for col in df.columns:
        c_clean = str(col).strip().lower().replace(" ", "_").replace("-", "_")
        if "zone" in c_clean:
            cols_map[col] = "zone"
        elif "ward" in c_clean:
            cols_map[col] = "ward"
        elif "pole_no" in c_clean or "pole_number" in c_clean or "pole" in c_clean:
            cols_map[col] = "pole_number"
        elif "old_lamp" in c_clean or "pole_with_old_lamp" in c_clean:
            cols_map[col] = "pole_old_lamp"
        elif "lamp_type" in c_clean or "lamp" in c_clean:
            cols_map[col] = "lamp_type"
        elif "lat" in c_clean:
            cols_map[col] = "latitude"
        elif "long" in c_clean or "lng" in c_clean:
            cols_map[col] = "longitude"
            
    df = df.rename(columns=cols_map)
    
    parsed_poles = []
    for idx, row in df.iterrows():
        raw_lamp = row.get("lamp_type", "")
        norm_lamp = normalize_lamp_type(raw_lamp)
        
        explicit_old_lamp = row.get("pole_old_lamp")
        if pd.isna(explicit_old_lamp) or str(explicit_old_lamp).strip() == "":
            old_lamp_cls = classify_old_lamp(norm_lamp)
        else:
            old_lamp_cls = str(explicit_old_lamp).strip()
            
        lat = float(row.get("latitude", 0.0)) if not pd.isna(row.get("latitude")) else 0.0
        lon = float(row.get("longitude", 0.0)) if not pd.isna(row.get("longitude")) else 0.0
        
        parsed_poles.append({
            "id": idx + 1,
            "pole_number": str(row.get("pole_number", f"P{idx+1:04d}")).strip(),
            "zone": str(row.get("zone", "")).strip(),
            "ward": str(row.get("ward", "")).strip(),
            "pole_old_lamp": old_lamp_cls,
            "lamp_type": norm_lamp,
            "latitude": lat,
            "longitude": lon
        })
        
    return parsed_poles
