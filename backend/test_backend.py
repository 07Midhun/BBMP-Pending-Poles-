import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from excel_parser import generate_sample_bbmp_data, classify_old_lamp, haversine_distance, normalize_lamp_type

def test_bbmp_backend_logic():
    print("Testing BBMP Backend Logic...")
    
    # 1. Test LED classification
    assert classify_old_lamp("FLED") == "LED", "FLED must map to LED"
    assert classify_old_lamp("LED-FLED") == "LED", "LED-FLED must map to LED"
    assert classify_old_lamp("LED-LED") == "LED", "LED-LED must map to LED"
    assert classify_old_lamp("LED") == "LED", "LED must map to LED"
    print("[PASS] LED Group Classifications Passed")
    
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
    
    # 4. Test Haversine Distance
    # P0001 (12.98204, 77.67365) to P0010 (12.98210, 77.67372)
    dist = haversine_distance(12.98204, 77.67365, 12.98210, 77.67372)
    print(f"[PASS] Haversine distance between P0001 and P0010: {dist:.2f} meters")
    assert 5.0 < dist < 25.0, "Distance should be around 10-15 meters"
    
    # 5. Test Sample Data Generation
    poles = generate_sample_bbmp_data()
    print(f"[PASS] Generated {len(poles)} sample BBMP poles across zones.")
    assert len(poles) > 0
    
    print("\nALL BACKEND UNIT TESTS PASSED SUCCESSFULLY!")

if __name__ == "__main__":
    test_bbmp_backend_logic()
