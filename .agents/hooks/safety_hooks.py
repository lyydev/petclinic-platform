#!/usr/bin/env python3
"""Antigravity lifecycle hooks for safety, security, and guidance."""

import json
import re
import sys

def pre_tool_block_destroy(payload):
    tool_call = payload.get("toolCall", {})
    cmd = tool_call.get("args", {}).get("CommandLine", "")
    if not cmd:
        return {"decision": "allow"}

    # Terraform / Terragrunt destroy
    if re.search(r'\b(terraform|terragrunt)\s+destroy\b', cmd, re.IGNORECASE):
        return {
            "decision": "deny",
            "reason": (
                "BLOCKED: 'terraform destroy' is not allowed via Antigravity.\n"
                "Destroying infrastructure must be done manually with explicit human oversight:\n"
                "  1. Run 'terraform plan -destroy' to review what will be destroyed\n"
                "  2. Review the plan carefully\n"
                "  3. Run 'terraform destroy' directly in your terminal."
            )
        }

    if re.search(r'\b(terraform|terragrunt)\s+apply\s+.*-destroy\b', cmd, re.IGNORECASE):
        return {
            "decision": "deny",
            "reason": "BLOCKED: 'terraform apply -destroy' is equivalent to 'terraform destroy'. Use your terminal directly if intentional."
        }

    # Block deleting prod namespace
    if re.search(r'kubectl\s+delete\s+(namespace|ns)\s+petclinic-prod\b', cmd, re.IGNORECASE):
        return {
            "decision": "deny",
            "reason": (
                "BLOCKED: Deleting the production namespace (petclinic-prod) is not allowed via Antigravity.\n"
                "This would destroy ALL production resources."
            )
        }

    # Block deleting critical resource types in prod namespace
    resource_match = re.search(r'kubectl\s+delete\s+(deployment|deploy|service|svc|ingress|ing|secret|configmap|cm|pvc|persistentvolumeclaim|daemonset|ds|statefulset|sts)\b', cmd, re.IGNORECASE)
    if resource_match and re.search(r'(-n|--namespace)[= ]?petclinic-prod\b', cmd, re.IGNORECASE):
        res_type = resource_match.group(1)
        return {
            "decision": "deny",
            "reason": f"BLOCKED: 'kubectl delete {res_type}' in petclinic-prod is not allowed via Antigravity to prevent downtime."
        }

    return {"decision": "allow"}


def pre_tool_block_dangerous_rm(payload):
    tool_call = payload.get("toolCall", {})
    cmd = tool_call.get("args", {}).get("CommandLine", "")
    if not cmd:
        return {"decision": "allow"}

    protected_dirs = ["terraform", "k8s", "helm", "helm-values", ".github", "docs", "scripts", ".claude", ".agents"]

    if re.search(r'\brm\s+(-[a-zA-Z]*[rf][a-zA-Z]*|--recursive|--force)\b', cmd):
        for d in protected_dirs:
            pattern = rf'\brm\s+.*(\s|/|^)\.?/?{re.escape(d)}(/|\s|$)'
            if re.search(pattern, cmd):
                return {
                    "decision": "deny",
                    "reason": f"BLOCKED: Cannot 'rm -rf' the '{d}/' directory containing critical infrastructure code."
                }

    return {"decision": "allow"}


def pre_tool_warn_apply_without_plan(payload):
    tool_call = payload.get("toolCall", {})
    cmd = tool_call.get("args", {}).get("CommandLine", "")
    if not cmd:
        return {"decision": "allow"}

    if re.search(r'\b(terraform|terragrunt)\s+apply\b', cmd, re.IGNORECASE):
        # Allow if a saved plan file (.out or .tfplan) is passed
        if re.search(r'apply\s+.*\.(out|tfplan)\b', cmd, re.IGNORECASE):
            return {"decision": "allow"}

        if "-auto-approve" in cmd:
            return {
                "decision": "ask",
                "reason": (
                    "WARNING: 'terraform apply -auto-approve' without a saved plan is risky.\n"
                    "Recommended: 1. terraform plan -out plan.out -> 2. terraform apply plan.out"
                )
            }

        return {
            "decision": "ask",
            "reason": (
                "WARNING: Running 'terraform apply' without a saved plan file.\n"
                "Recommended: 1. terraform plan -out plan.out -> 2. Review plan -> 3. terraform apply plan.out"
            )
        }

    return {"decision": "allow"}


def pre_tool_block_secret_commit(payload):
    tool_call = payload.get("toolCall", {})
    cmd = tool_call.get("args", {}).get("CommandLine", "")
    if not cmd:
        return {"decision": "allow"}

    if re.search(r'\bgit\s+(add|commit)\b', cmd):
        if re.search(r'\bgit\s+add\s+(-A|--all|\.)(\s|$)', cmd):
            return {
                "decision": "deny",
                "reason": (
                    "BLOCKED: 'git add .' / 'git add -A' can accidentally stage secret files.\n"
                    "Instead, stage files explicitly by name (e.g. git add terraform/modules/vpc/main.tf)."
                )
            }

        secret_patterns = [
            r'\.env($|\s|/)',
            r'\.tfvars($|\s)',
            r'\.pem($|\s)',
            r'\.key($|\s)',
            r'\.p12($|\s)',
            r'\.pfx($|\s)',
            r'kubeconfig',
            r'aws-credentials',
            r'credentials\.json',
            r'credentials\.yaml'
        ]
        for pat in secret_patterns:
            if re.search(pat, cmd, re.IGNORECASE):
                return {
                    "decision": "deny",
                    "reason": f"BLOCKED: Detected potential secret file matching '{pat}' in git staging/commit command."
                }

    return {"decision": "allow"}


def pre_tool_block_mcp_destroy(payload):
    tool_call = payload.get("toolCall", {})
    args = tool_call.get("args", {})
    # Check MCP arguments for command: "destroy"
    inner_args = args.get("Arguments", {})
    if isinstance(inner_args, dict):
        if inner_args.get("command") == "destroy":
            return {
                "decision": "deny",
                "reason": "BLOCKED: 'destroy' via MCP Terraform tool is not allowed. Destroy must be executed manually in a terminal."
            }
    if args.get("command") == "destroy":
        return {
            "decision": "deny",
            "reason": "BLOCKED: 'destroy' via MCP Terraform tool is not allowed."
        }

    return {"decision": "allow"}


def post_tool_suggest_validate(payload):
    tool_call = payload.get("toolCall", {})
    args = tool_call.get("args", {})
    file_path = args.get("TargetFile") or args.get("AbsolutePath") or args.get("path") or ""

    tips = []
    if file_path.endswith(".tf"):
        tips.append("Tip: Terraform file edited. Run 'terraform validate' and 'terraform fmt -check'.")
    elif "k8s/" in file_path and (file_path.endswith(".yaml") or file_path.endswith(".yml")):
        tips.append(f"Tip: K8s manifest edited. Run 'kubectl apply --dry-run=client -f {file_path}'.")
    elif ("helm/" in file_path or "helm-values/" in file_path) and (file_path.endswith((".yaml", ".yml", ".tpl"))):
        tips.append("Tip: Helm file edited. Validate with 'helm template' and 'helm lint'.")
    elif ".github/workflows/" in file_path and file_path.endswith((".yaml", ".yml")):
        tips.append("Tip: GitHub Actions workflow edited. Review with pipeline-reviewer subagent.")

    if tips:
        # Output tip as system message or stderr for visibility
        sys.stderr.write("\n".join(tips) + "\n")

    return {}


HOOKS = {
    "block-destroy": pre_tool_block_destroy,
    "block-dangerous-rm": pre_tool_block_dangerous_rm,
    "warn-apply-without-plan": pre_tool_warn_apply_without_plan,
    "block-secret-commit": pre_tool_block_secret_commit,
    "block-mcp-destroy": pre_tool_block_mcp_destroy,
    "suggest-validate": post_tool_suggest_validate,
}

def main():
    if len(sys.argv) < 2:
        print(json.dumps({"decision": "allow"}))
        return

    hook_name = sys.argv[1]
    handler = HOOKS.get(hook_name)
    if not handler:
        print(json.dumps({"decision": "allow"}))
        return

    try:
        raw_input = sys.stdin.read()
        payload = json.loads(raw_input) if raw_input.strip() else {}
    except Exception:
        payload = {}

    result = handler(payload)
    print(json.dumps(result))

if __name__ == "__main__":
    main()
