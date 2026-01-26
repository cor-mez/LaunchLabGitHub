#!/usr/bin/env python3

import sys
import pandas as pd
import matplotlib.pyplot as plt

# ============================================================
# Telemetry event codes (Phase-2)
# ============================================================

FAST9_CODE         = 0x41
RS_METRIC_CODE     = 0x20    # zmax + point count
LOCALITY_CODE      = 0x21    # rowSpanFraction + adjacentRowCorrelation
STRUCTURE_CODE     = 0x22    # structureRatio + peakRowEnergy

# Outcome / classification
OBSERVABLE_CODE    = 0x55

# Row-span classification
SPAN_NARROW_CODE   = 0x61
SPAN_MODERATE_CODE = 0x62
SPAN_WIDE_CODE     = 0x63

# Refusals
REFUSE_LOW_SLOPE     = 0x53
REFUSE_GLOBAL        = 0x52
REFUSE_FLICKER       = 0x54
REFUSE_INSUFFICIENT  = 0x50

# ============================================================
# Load CSV
# ============================================================

if len(sys.argv) != 2:
    print("Usage: python analyze_rs.py <telemetry.csv>")
    sys.exit(1)

csv_path = sys.argv[1]
df = pd.read_csv(csv_path)

# Drop default / empty rows
df = df[df["timestamp"] > 0].copy()

if df.empty:
    print("CSV contains no telemetry events.")
    sys.exit(0)

# ============================================================
# Split event types
# ============================================================

fast9      = df[df["code"] == FAST9_CODE]
rs         = df[df["code"] == RS_METRIC_CODE]
locality   = df[df["code"] == LOCALITY_CODE]
structure  = df[df["code"] == STRUCTURE_CODE]

observable = df[df["code"] == OBSERVABLE_CODE]

span_narrow   = df[df["code"] == SPAN_NARROW_CODE]
span_moderate = df[df["code"] == SPAN_MODERATE_CODE]
span_wide     = df[df["code"] == SPAN_WIDE_CODE]

# ============================================================
# Summary stats
# ============================================================

print("\n=== RS Phase-2 Telemetry Summary ===")
print(f"Total events: {len(df)}")
print(f"FAST9 events: {len(fast9)}")
print(f"RS metric frames: {len(rs)}")
print(f"Observable frames: {len(observable)}")

if not rs.empty:
    print(f"zmax median: {rs['valueA'].median():.6f}")
    print(f"zmax max:    {rs['valueA'].max():.6f}")

if not locality.empty:
    print(f"row span median: {locality['valueA'].median():.3f}")
    print(f"row span max:    {locality['valueA'].max():.3f}")

if not structure.empty:
    print(f"structure ratio median: {structure['valueA'].median():.3f}")
    print(f"structure ratio max:    {structure['valueA'].max():.3f}")

print("\nRow-span classification counts:")
print(f"  narrow:   {len(span_narrow)}")
print(f"  moderate: {len(span_moderate)}")
print(f"  wide:     {len(span_wide)}")

print("\nRefusal counts:")
print(f"  insufficient points: {len(df[df['code']==REFUSE_INSUFFICIENT])}")
print(f"  low slope:           {len(df[df['code']==REFUSE_LOW_SLOPE])}")
print(f"  too global:          {len(df[df['code']==REFUSE_GLOBAL])}")
print(f"  flicker-aligned:     {len(df[df['code']==REFUSE_FLICKER])}")

# ============================================================
# Plot 1: zmax over time
# ============================================================

plt.figure(figsize=(10, 4))
plt.plot(rs["timestamp"], rs["valueA"], ".", alpha=0.6)
plt.xlabel("Time (s)")
plt.ylabel("zmax (RS shear)")
plt.title("RS shear (zmax) over time")
plt.grid(True)

# ============================================================
# Plot 2: FAST9 yield over time
# ============================================================

plt.figure(figsize=(10, 4))
plt.plot(fast9["timestamp"], fast9["valueA"], ".", alpha=0.6)
plt.xlabel("Time (s)")
plt.ylabel("FAST9 point count")
plt.title("FAST9 feature yield over time")
plt.grid(True)

# ============================================================
# Plot 3: Row-span vs zmax
# ============================================================

if not locality.empty and not rs.empty:
    merged_loc = pd.merge_asof(
        rs.sort_values("timestamp"),
        locality.sort_values("timestamp"),
        on="timestamp",
        tolerance=0.002,
        direction="nearest",
        suffixes=("_z", "_loc"),
    )

    plt.figure(figsize=(6, 6))
    plt.scatter(
        merged_loc["valueA_loc"],
        merged_loc["valueA_z"],
        alpha=0.5
    )
    plt.xlabel("Row span fraction")
    plt.ylabel("zmax")
    plt.title("RS shear vs row span")
    plt.grid(True)

# ============================================================
# Plot 4: Structure ratio vs zmax (NEW CORE PLOT)
# ============================================================

if not structure.empty and not rs.empty:
    merged_struct = pd.merge_asof(
        rs.sort_values("timestamp"),
        structure.sort_values("timestamp"),
        on="timestamp",
        tolerance=0.002,
        direction="nearest",
        suffixes=("_z", "_s"),
    )

    plt.figure(figsize=(6, 6))
    plt.scatter(
        merged_struct["valueA_s"],   # structure ratio
        merged_struct["valueA_z"],   # zmax
        alpha=0.5
    )
    plt.xlabel("Structure ratio (peak / mean row energy)")
    plt.ylabel("zmax")
    plt.title("RS structure vs shear (physics discriminator)")
    plt.grid(True)

# ============================================================
# Plot 5: Span-class overlay over time
# ============================================================

if not rs.empty:
    plt.figure(figsize=(10, 4))
    plt.scatter(rs["timestamp"], rs["valueA"], s=10, alpha=0.15, label="all RS frames")

    plt.scatter(span_narrow["timestamp"], span_narrow["valueA"],
                s=30, label="narrow span", marker="o")
    plt.scatter(span_moderate["timestamp"], span_moderate["valueA"],
                s=30, label="moderate span", marker="^")
    plt.scatter(span_wide["timestamp"], span_wide["valueA"],
                s=30, label="wide span", marker="s")

    plt.xlabel("Time (s)")
    plt.ylabel("zmax")
    plt.title("RS frames by row-span class")
    plt.legend()
    plt.grid(True)

plt.show()

# ============================================================
# Final interpretation heuristic (NON-authoritative)
# ============================================================

print("\n=== Interpretation Heuristic (NOT authority) ===")

if rs.empty:
    print("❌ No RS metrics recorded.")
elif rs["valueA"].max() < 2.5 * rs["valueA"].median():
    print("⚠️ RS signal exists but weak separation from baseline.")
    print("→ Increase contrast, marker density, or controlled motion.")
else:
    print("✅ RS signal separates from static baseline.")
    print("→ Phase-2 observability confirmed; proceed to structured validation.")