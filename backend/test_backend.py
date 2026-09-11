import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from excel_parser import (
    generate_sample_schnell_iot_data,
    classify_old_lamp,
    haversine_distance,
    normalize_lamp_type,
    compute_pending_poles
)

def test_bbmp_phase1_backend_logic():
    print("Testing Phase 1 Backend Logic...")
    
    # 1. Test LED classification with LED-FLED
    assert classify_old_lamp("FLED") == "LED", "FLED must map to LED"
    assert classify_old_lamp("LED-FLED") == "LED", "LED-FLED must map to LED"
    assert classify_old_lamp("LED-LED") == "LED", "LED-LED must map to LED"
    assert classify_old_lamp("LED") == "LED", "LED must map to LED"
    print("[PASS] LED Group Classifications (including LED-FLED) Passed")
    
    # 2. Test Empty classification
    assert classify_old_lamp("-") == "Empty", "- must map to Empty"
    assert classify_old_lamp("Blank") == "Empty", "Blank must map to Empty"
    assert classify_old_lamp("") == "Empty", "Empty string must map to Empty"
    print("[PASS] Empty Group Classifications Passed")
    
    # 3. Test Non-LED classification
    assert classify_old_lamp("CFL") == "Non-LED", "CFL must map to Non-LED"
    assert classify_old_lamp("Sodium") == "Non-LED", "Sodium must map to Non-LED"
    assert classify_old_lamp("Halogen") == "Non-LED", "Halogen must map to Non-LED"
    assert classify_old_lamp("Tube") == "Non-LED", "Tube must map to Non-LED"
    print("[PASS] Non-LED Group Classifications Passed")
    
    # 4. Test Master Data vs Lamp Installation Report Diffing (with duplicates)
    master = [
        {"pole_number": "P0001", "zone": "East"},
        {"pole_number": "P0010", "zone": "East"},
        {"pole_number": "P0100", "zone": "East"},
        {"pole_number": "P0200", "zone": "East"},
        {"pole_number": "P0300", "zone": "East"},
    ]
    # Installed report has P0001 (duplicated), P0100 (duplicated), P0200
    installed_report = ["P0001", "P0001", "P0100", "P0100", "P0200"]
    
    pending = compute_pending_poles(master, installed_report)
    pending_numbers = [p["pole_number"] for p in pending]
    
    assert pending_numbers == ["P0010", "P0300"], f"Expected ['P0010', 'P0300'], got {pending_numbers}"
    print(f"[PASS] Pending Pole Diffing Passed: Master (5) - Installed (3 unique) = Pending ({len(pending)})")
    
    # 5. Test Sample Data Generation
    iot_data = generate_sample_schnell_iot_data()
    assert len(iot_data["master_poles"]) > len(iot_data["pending_poles"])
    assert "region" in iot_data["master_poles"][0]
    print(f"[PASS] Sample Data Generated: {len(iot_data['master_poles'])} Master, {len(iot_data['pending_poles'])} Pending")

    print("\nALL PHASE 1 BACKEND UNIT TESTS PASSED SUCCESSFULLY!")

if __name__ == "__main__":
    test_bbmp_phase1_backend_logic()
