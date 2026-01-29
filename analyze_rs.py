#!/usr/bin/env python3

import sys
import os
import pandas as pd
import matplotlib.pyplot as plt
from matplotlib.backends.backend_pdf import PdfPages

# ============================================================
# Telemetry event codes (Phase-4 aligned)
# ============================================================

FAST9_CODE          = 0x41
RS_METRIC_CODE      = 0x20
LOCALITY_CODE       = 0x21
STRUCTURE_CODE      = 0x22

PHASE3_SUMMARY_CODE = 0x80
PHASE3_SPAN_CODE    = 0x81
PHASE3_OUTCOME_CODE = 0x82

PHASE4_PASS_CODE    = 0x90
PHASE4_FAIL_CODE    = 0x91

# ============================================================
# CLI handling (BATCH MODE + LABELS)
# ============================================================

if len(sys.argv) < 2:
    print("Usage: python analyze_rs.py <file.csv[:label]> ...")
    sys.exit(1)

inputs = []
for arg in sys.argv[1:]:
    if ":" in arg:
        path, label = arg.split(":", 1)
    else:
        path = arg
        label = os.path.basename(arg)
    inputs.append((path, label))

# ============================================================
# Helpers
# ============================================================

def load_csv(path):
    df = pd.read_csv(path)
    df = df[df["timestamp"] > 0].copy()
    if df.empty:
        return None
    return df.sort_values("timestamp").reset_index(drop=True)

def summarize(df):
    return {
        "total": len(df),
        "fast9": len(df[df["code"] == FAST9_CODE]),
        "rs": len(df[df["code"] == RS_METRIC_CODE]),
        "phase3": len(df[df["code"] == PHASE3_SUMMARY_CODE]),
        "pass": len(df[df["code"] == PHASE4_PASS_CODE]),
        "fail": len(df[df["code"] == PHASE4_FAIL_CODE]),
        "zmax_median": df[df["code"] == RS_METRIC_CODE]["valueA"].median()
                        if not df[df["code"] == RS_METRIC_CODE].empty else 0,
        "zmax_max": df[df["code"] == RS_METRIC_CODE]["valueA"].max()
                        if not df[df["code"] == RS_METRIC_CODE].empty else 0,
        "zwin_median": df[df["code"] == PHASE3_SUMMARY_CODE]["valueA"].median()
                        if not df[df["code"] == PHASE3_SUMMARY_CODE].empty else 0,
        "zwin_max": df[df["code"] == PHASE3_SUMMARY_CODE]["valueA"].max()
                        if not df[df["code"] == PHASE3_SUMMARY_CODE].empty else 0,
        "struct_peak": df[df["code"] == PHASE3_SUMMARY_CODE]["valueB"].max()
                        if not df[df["code"] == PHASE3_SUMMARY_CODE].empty else 0,
    }

def verdict_text(s):
    if s["pass"] > 0:
        return "✅ Phase-4 PASS windows present"
    elif s["rs"] > 0:
        return "⚠️ RS signal present, no Phase-4 PASS"
    else:
        return "❌ No RS signal detected"

# ============================================================
# Batch PDF export
# ============================================================

pdf_name = "rs_phase4_batch_analysis.pdf"
print(f"\n📄 Writing batch analysis to {pdf_name}")

summaries = []
pass_windows = []

with PdfPages(pdf_name) as pdf:

    # --------------------------------------------------------
    # Cover page
    # --------------------------------------------------------
    fig = plt.figure(figsize=(8.5, 11))
    plt.axis("off")
    plt.text(0.5, 0.85, "LaunchLab — Phase-4 RS Batch Analysis",
             ha="center", fontsize=18, weight="bold")
    plt.text(0.5, 0.75, "Tests included:", ha="center", fontsize=12)

    y = 0.7
    for _, label in inputs:
        plt.text(0.5, y, label, ha="center", fontsize=10)
        y -= 0.035

    pdf.savefig(fig)
    plt.close(fig)

    # --------------------------------------------------------
    # Per-test analysis
    # --------------------------------------------------------
    for path, label in inputs:

        df = load_csv(path)

        print(f"\n=== {label} ===")

        if df is None:
            print("No telemetry data.")
            continue

        summary = summarize(df)
        summaries.append((label, summary))

        # ---------- Terminal summary ----------
        print(f"Total telemetry events: {summary['total']}")
        print(f"FAST9 frames:           {summary['fast9']}")
        print(f"RS metric frames:       {summary['rs']}")
        print(f"Phase-3 windows:        {summary['phase3']}")
        print(f"Phase-4 PASS:           {summary['pass']}   FAIL: {summary['fail']}")
        print(f"RS zmax median:         {summary['zmax_median']:.6f}")
        print(f"RS zmax max:            {summary['zmax_max']:.6f}")
        print(f"Window zmax median:     {summary['zwin_median']:.6f}")
        print(f"Window zmax max:        {summary['zwin_max']:.6f}")
        print(f"Peak structure cons.:   {summary['struct_peak']:.3f}")
        print(f"Verdict: {verdict_text(summary)}")

        fast9   = df[df["code"] == FAST9_CODE]
        rs      = df[df["code"] == RS_METRIC_CODE]
        phase3  = df[df["code"] == PHASE3_SUMMARY_CODE]
        p4_pass = df[df["code"] == PHASE4_PASS_CODE]
        p4_fail = df[df["code"] == PHASE4_FAIL_CODE]

        if not p4_pass.empty:
            tmp = p4_pass.copy()
            tmp["label"] = label
            pass_windows.append(tmp)

        # ---------------- Summary page ----------------
        fig = plt.figure(figsize=(8.5, 11))
        plt.axis("off")
        plt.text(0.5, 0.9, label, ha="center", fontsize=16, weight="bold")

        info = (
            f"FAST9 frames: {summary['fast9']}\n"
            f"RS frames: {summary['rs']}\n"
            f"Phase-3 windows: {summary['phase3']}\n"
            f"Phase-4 PASS: {summary['pass']}   FAIL: {summary['fail']}\n\n"
            f"RS zmax median: {summary['zmax_median']:.4f}\n"
            f"RS zmax max: {summary['zmax_max']:.4f}\n"
            f"Peak structure consistency: {summary['struct_peak']:.3f}"
        )

        plt.text(0.5, 0.65, info, ha="center", fontsize=12)
        pdf.savefig(fig)
        plt.close(fig)

        # ---------------- RS shear ----------------
        fig = plt.figure(figsize=(10, 4))
        plt.scatter(rs["timestamp"], rs["valueA"], s=8, alpha=0.5)
        plt.xlabel("Time (s)")
        plt.ylabel("zmax")
        plt.title("Phase-2 RS shear (frame-level)")
        plt.grid(True)
        pdf.savefig(fig)
        plt.close(fig)

        # ---------------- Phase-3 envelopes ----------------
        fig = plt.figure(figsize=(10, 4))
        plt.scatter(phase3["timestamp"], phase3["valueA"], s=25, alpha=0.7)
        plt.xlabel("Time (s)")
        plt.ylabel("zmaxPeak")
        plt.title("Phase-3 RS window envelopes")
        plt.grid(True)
        pdf.savefig(fig)
        plt.close(fig)

        # ---------------- Phase-4 verdicts ----------------
        fig = plt.figure(figsize=(10, 4))
        plt.scatter(p4_fail["timestamp"], p4_fail["valueA"],
                    s=40, marker="x", label="FAIL", alpha=0.6)
        plt.scatter(p4_pass["timestamp"], p4_pass["valueA"],
                    s=60, marker="o", label="PASS", alpha=0.8)
        plt.xlabel("Time (s)")
        plt.ylabel("zmaxPeak")
        plt.title("Phase-4 PASS / FAIL windows")
        plt.legend()
        plt.grid(True)
        pdf.savefig(fig)
        plt.close(fig)

    # --------------------------------------------------------
    # PASS-only overlay comparison
    # --------------------------------------------------------
    if pass_windows:
        fig = plt.figure(figsize=(10, 6))
        for dfp in pass_windows:
            plt.scatter(
                dfp["valueB"],
                dfp["valueA"],
                s=70,
                alpha=0.8,
                label=dfp["label"].iloc[0]
            )

        plt.xlabel("Structure Consistency")
        plt.ylabel("zmaxPeak")
        plt.title("Phase-4 PASS Windows — Cross-Test Comparison")
        plt.legend()
        plt.grid(True)
        pdf.savefig(fig)
        plt.close(fig)

print("\n✅ Batch PDF export complete.")

# ============================================================
# Final batch summary
# ============================================================

print("\n=== Batch Summary ===")
for label, s in summaries:
    print(f"{label}: {verdict_text(s)}")