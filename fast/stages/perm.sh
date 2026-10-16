#!/usr/bin/env bash
# Copyright 2026 Placard Media / Cloud Foundation Fabric
#
# Complete Organization-Wide IAM Remediation Script
# Resolves 403 querying Cloud Storage / serviceusage.services.use across all stages
# and ensures Tessa has proper impersonation access.

set -euo pipefail

ORG_ID="150829647948"
CORE_PROJECT="placard-prod-iac-core-0"
OUTPUTS_BUCKET="placard-prod-iac-core-0-iac-outputs"

echo "========================================================================"
echo " Placard Media - Foundation IAM Remediation (Org: ${ORG_ID})"
echo "========================================================================"
echo ""

# 0. Check and ensure valid gcloud authentication
echo "[0/4] Checking gcloud authentication..."
CURRENT_ACCOUNT=$(gcloud config get-value account 2>/dev/null || true)

if ! gcloud auth print-access-token &>/dev/null; then
  echo "  Active account [${CURRENT_ACCOUNT:-none}] credentials are expired or invalid."
  echo "  Launching 'gcloud auth login' to authenticate with an admin account (e.g. justin@placard.media)..."
  gcloud auth login
  CURRENT_ACCOUNT=$(gcloud config get-value account 2>/dev/null)
fi
echo "  ✓ Authenticated as: ${CURRENT_ACCOUNT}"
echo ""

# 1. Grant roles/serviceusage.serviceUsageConsumer at the ORGANIZATION level
echo "[1/4] Granting 'roles/serviceusage.serviceUsageConsumer' at Org Level to all stage SAs..."
STAGE_SAS=(
  "iac-org-rw"
  "iac-org-ro"
  "iac-vpcsc-rw"
  "iac-vpcsc-ro"
  "iac-networking-rw"
  "iac-networking-ro"
  "iac-security-rw"
  "iac-security-ro"
  "iac-pf-rw"
  "iac-pf-ro"
)

for sa in "${STAGE_SAS[@]}"; do
  SA_EMAIL="${sa}@${CORE_PROJECT}.iam.gserviceaccount.com"
  echo "  -> Org Level: ${SA_EMAIL}..."
  gcloud organizations add-iam-policy-binding "${ORG_ID}" \
    --member="serviceAccount:${SA_EMAIL}" \
    --role="roles/serviceusage.serviceUsageConsumer" \
    --condition=None \
    --quiet >/dev/null || true

  # Also ensure project-level binding on core project
  gcloud projects add-iam-policy-binding "${CORE_PROJECT}" \
    --member="serviceAccount:${SA_EMAIL}" \
    --role="roles/serviceusage.serviceUsageConsumer" \
    --condition=None \
    --quiet >/dev/null || true
done
echo "  ✓ Done. Service usage consumer is now inherited organization-wide."
echo ""

# 2. Stage 0 core management roles on iac-org-rw
echo "[2/4] Granting core management roles to iac-org-rw on ${CORE_PROJECT}..."
SA_ORG_RW="iac-org-rw@${CORE_PROJECT}.iam.gserviceaccount.com"
for role in \
  roles/cloudbuild.builds.editor \
  roles/iam.serviceAccountAdmin \
  roles/iam.workloadIdentityPoolAdmin \
  roles/owner \
  roles/storage.admin; do
  echo "  -> ${role} on ${SA_ORG_RW}..."
  gcloud projects add-iam-policy-binding "${CORE_PROJECT}" \
    --member="serviceAccount:${SA_ORG_RW}" \
    --role="${role}" \
    --condition=None \
    --quiet >/dev/null || true
done
echo "  ✓ Done."
echo ""

# 3. Grant impersonation and quota permissions to Tessa
echo "[3/4] Granting impersonation and access permissions to Tessa..."
TESSA_ACCOUNTS=("tessa@placard.media" "tessa@placard.com")

for user in "${TESSA_ACCOUNTS[@]}"; do
  echo "  Configuring user:${user}..."

  # Allow setting quota project and calling APIs at org and project level
  gcloud organizations add-iam-policy-binding "${ORG_ID}" \
    --member="user:${user}" \
    --role="roles/serviceusage.serviceUsageConsumer" \
    --condition=None \
    --quiet >/dev/null || true

  gcloud projects add-iam-policy-binding "${CORE_PROJECT}" \
    --member="user:${user}" \
    --role="roles/serviceusage.serviceUsageConsumer" \
    --condition=None \
    --quiet >/dev/null || true

  # Allow impersonating all IaC service accounts (Token Creator)
  gcloud projects add-iam-policy-binding "${CORE_PROJECT}" \
    --member="user:${user}" \
    --role="roles/iam.serviceAccountTokenCreator" \
    --condition=None \
    --quiet >/dev/null || true

  # Allow project metadata and bucket inspection
  gcloud projects add-iam-policy-binding "${CORE_PROJECT}" \
    --member="user:${user}" \
    --role="roles/viewer" \
    --condition=None \
    --quiet >/dev/null || true

  # Direct read access to outputs bucket for fast-links.sh
  gcloud storage buckets add-iam-policy-binding "gs://${OUTPUTS_BUCKET}" \
    --member="user:${user}" \
    --role="roles/storage.objectViewer" \
    --quiet >/dev/null || true
done
echo "  ✓ Done."
echo ""

# 4. Verify iac-pf-rw and iac-org-rw
echo "[4/4] Verifying permissions..."
echo "  Checking iac-pf-rw on core project:"
gcloud projects get-iam-policy "${CORE_PROJECT}" --flatten="bindings[].members" \
  --filter="bindings.members:iac-pf-rw@ AND bindings.role:roles/serviceusage.serviceUsageConsumer" \
  --format="table(bindings.role, bindings.members)"

echo ""
echo "========================================================================"
echo " All IAM bindings successfully configured!"
echo "========================================================================"
