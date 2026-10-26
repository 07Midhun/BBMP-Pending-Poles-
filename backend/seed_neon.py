import os
import sys
from pathlib import Path

BASE_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(BASE_DIR))

from dotenv import load_dotenv
load_dotenv()

from database import engine, SessionLocal, init_db
from models_db import PoleDB
from excel_parser import generate_sample_schnell_iot_data, parse_excel_dataset
from sqlalchemy.dialects.postgresql import insert

def seed_database():
    if engine is None or SessionLocal is None:
        print("ERROR: DATABASE_URL is not set or invalid in environment.")
        return False

    print("Initializing database schema...")
    init_db()

    session = SessionLocal()
    try:
        # Check if poles already exist
        existing_count = session.query(PoleDB).count()
        print(f"Current poles in database: {existing_count}")

        # Try to parse Excel if present, else fallback to generated sample data
        excel_path = BASE_DIR / "Pole_survey_report(BBMP).xlsx"
        poles_to_insert = []

        if excel_path.is_file():
            print(f"Reading master survey poles from {excel_path.name}...")
            try:
                poles_to_insert = parse_excel_dataset(str(excel_path))
                print(f"Loaded {len(poles_to_insert)} poles from Excel.")
            except Exception as e:
                print(f"Could not parse Excel ({e}), generating default survey dataset...")
        
        if not poles_to_insert:
            print("Generating initial survey dataset...")
            iot_data = generate_sample_schnell_iot_data()
            poles_to_insert = iot_data["master_poles"]
            installed_set = set(iot_data["installed_report"])
        else:
            installed_set = set()

        print(f"Preparing {len(poles_to_insert)} records for Neon insertion...")
        
        batch_size = 500
        total_inserted = 0
        
        for i in range(0, len(poles_to_insert), batch_size):
            batch = poles_to_insert[i:i + batch_size]
            records = []
            for p in batch:
                pole_no = str(p.get("pole_number", "")).strip().upper()
                if not pole_no:
                    continue
                records.append({
                    "pole_number": pole_no,
                    "region": str(p.get("region", "EAST")).strip().upper(),
                    "zone": str(p.get("zone", "")).strip(),
                    "ward": str(p.get("ward", "")).strip(),
                    "pole_old_lamp": str(p.get("pole_old_lamp", "Empty")).strip(),
                    "lamp_type": str(p.get("lamp_type", "-")).strip(),
                    "latitude": float(p.get("latitude", 0.0)),
                    "longitude": float(p.get("longitude", 0.0)),
                    "is_installed": pole_no in installed_set,
                    "uploaded_slots": [],
                })

            if not records:
                continue

            stmt = insert(PoleDB).values(records)
            stmt = stmt.on_conflict_do_update(
                index_elements=["pole_number"],
                set_={
                    "region": stmt.excluded.region,
                    "zone": stmt.excluded.zone,
                    "ward": stmt.excluded.ward,
                    "pole_old_lamp": stmt.excluded.pole_old_lamp,
                    "lamp_type": stmt.excluded.lamp_type,
                    "latitude": stmt.excluded.latitude,
                    "longitude": stmt.excluded.longitude,
                }
            )
            session.execute(stmt)
            session.commit()
            total_inserted += len(records)
            print(f"  Inserted/Updated {total_inserted}/{len(poles_to_insert)} poles...")

        final_count = session.query(PoleDB).count()
        print(f"\nSUCCESS: Neon database now contains {final_count} poles!")
        return True
    except Exception as exc:
        session.rollback()
        print(f"ERROR while seeding database: {exc}")
        return False
    finally:
        session.close()

if __name__ == "__main__":
    seed_database()
