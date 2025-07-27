#!/usr/bin/env python3

import json
import sys
import subprocess

# Read JSON input from Terraform
input_data = json.load(sys.stdin)
region = input_data.get("region")

if not region:
    print(json.dumps({"error": "No region provided"}))
    sys.exit(1)

try:
    # Get versions using AWS CLI
    cmd = [
        "aws", "eks", "describe-addon-versions",
        "--addon-name", "vpc-cni",
        "--region", region
    ]
    output = subprocess.check_output(cmd)
    parsed = json.loads(output)

    # Get list of Kubernetes versions supported by this addon
    versions = parsed["addons"][0]["addonVersions"][0]["compatibilities"]
    k8s_versions = [v["clusterVersion"] for v in versions]
    # Sort and return the latest version
    latest_version = sorted(k8s_versions, reverse=True)[0]

    print(json.dumps({"latest_version": latest_version}))
except Exception as e:
    print(json.dumps({"error": str(e)}))
    sys.exit(1)
