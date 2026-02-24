#!/usr/bin/env python3
import sys
import requests
import boto3
import re
import time

# --- CONFIGURATION ---
ALB_DNS = sys.argv[1] if len(sys.argv) > 1 else None
ASG_NAME = "devops-poc-asg" 
REGION = "us-east-1"
MAX_RETRIES = 12  # 12 * 25 seconds = 5 minutes total wait time
RETRY_INTERVAL = 25

if not ALB_DNS:
    print("Usage: python validate_endpoints.py <ALB_DNS>")
    sys.exit(1)

# Service URLs (These use the ALB Listener Rules you defined)
SERVICE_CONFIGS = {
    "Service1": {
        "health": f"http://{ALB_DNS}/service1/health",
        "metrics": f"http://{ALB_DNS}/service1/metrics"
    },
    "Service2": {
        "health": f"http://{ALB_DNS}/service2/health",
        "metrics": f"http://{ALB_DNS}/service2/metrics"
    }
}

def check_health(url, service_name):
    """Check /health endpoint for 'healthy' string"""
    try:
        r = requests.get(url, timeout=5)
        if r.status_code == 200 and 'healthy' in r.text.lower():
            print(f"  [OK] {service_name} health check passed")
            return True
        print(f"  [FAIL] {service_name} returned {r.status_code}: {r.text[:50]}")
    except Exception as e:
        print(f"  [ERROR] {service_name} unreachable: {e}")
    return False

def check_prometheus_metrics(url, service_name):
    """Parse Prometheus counters from /metrics"""
    try:
        r = requests.get(url, timeout=5)
        if r.status_code != 200:
            return False
        
        found_metrics = False
        for line in r.text.splitlines():
            if line.startswith('#') or not line.strip():
                continue
            # Matches: name_requests_total 10
            match = re.match(r'(\w+)_requests_total\s+(\d+)', line)
            if match:
                found_metrics = True
                print(f"  [INFO] {service_name} Metric: {match.group(1)}={match.group(2)}")
        
        return found_metrics
    except Exception as e:
        print(f"  [ERROR] {service_name} metrics failed: {e}")
        return False

def check_asg_instances(asg_name, region):
    """Check if ASG has the minimum required instances"""
    try:
        client = boto3.client("autoscaling", region_name=region)
        response = client.describe_auto_scaling_groups(AutoScalingGroupNames=[asg_name])
        if not response["AutoScalingGroups"]:
            print(f"  [FAIL] ASG {asg_name} not found")
            return False
            
        instances = response["AutoScalingGroups"][0]["Instances"]
        healthy_instances = [i for i in instances if i["HealthStatus"] == "Healthy"]
        print(f"  [INFO] ASG '{asg_name}': {len(healthy_instances)} healthy instance(s) found")
        return len(healthy_instances) >= 2
    except Exception as e:
        print(f"  [ERROR] ASG check failed: {e}")
        return False

def main():
    print(f"\n--- Starting Validation for ALB: {ALB_DNS} ---")
    
    # --- PHASE 1: Wait for Availability ---
    print(f"[1/3] Waiting for ALB and containers to warm up...")
    all_reachable = False
    for attempt in range(MAX_RETRIES):
        checks = [requests.get(cfg["health"], timeout=2).status_code == 200 
                  for cfg in SERVICE_CONFIGS.values()]
        
        if all(checks):
            print("  [SUCCESS] All endpoints are responding!")
            all_reachable = True
            break
        
        print(f"  ...Attempt {attempt+1}/{MAX_RETRIES}: Services not ready yet. Sleeping {RETRY_INTERVAL}s...")
        time.sleep(RETRY_INTERVAL)

    if not all_reachable:
        print("\n[FATAL] Services failed to become ready within 5 minutes.")
        sys.exit(1)

    # --- PHASE 2: Detailed Validation ---
    print("\n[2/3] Running detailed endpoint checks...")
    success = True
    
    for name, cfg in SERVICE_CONFIGS.items():
        if not check_health(cfg["health"], name): success = False
        if not check_prometheus_metrics(cfg["metrics"], name): success = False

    # --- PHASE 3: Infrastructure Check ---
    print("\n[3/3] Checking ASG Infrastructure...")
    if not check_asg_instances(ASG_NAME, REGION):
        success = False

    # --- FINAL VERDICT ---
    if success:
        print("\nDeployment Verified Successfully")
        sys.exit(0)
    else:
        print("\nDeployment Validation Failed")
        sys.exit(1)

if __name__ == "__main__":
    main()