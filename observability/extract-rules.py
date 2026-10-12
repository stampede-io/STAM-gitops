#!/usr/bin/env python3
"""STAM-402: promtool only understands plain Prometheus rule files
(top-level `groups:`), not the PrometheusRule CRD wrapper (apiVersion/
kind/metadata/spec) alerts.yaml is written as for kubectl/ArgoCD. This
pulls `.spec` out so the test always runs against the real file instead
of a hand-duplicated copy that could drift from it.
"""
import sys
import yaml

src, dst = sys.argv[1], sys.argv[2]
with open(src, encoding="utf-8") as f:
    doc = yaml.safe_load(f)

with open(dst, "w", encoding="utf-8") as f:
    yaml.safe_dump(doc["spec"], f, sort_keys=False)
