#!/bin/bash
set -euo pipefail


usage() {
  cat <<EOF
Usage: $0 --org-id ORG_ID --billing-account BILLING_ACCOUNT_ID

Options:
  --org-id          GCP Organization ID
  --billing-account GCP Billing Account ID
  -h, --help        Show this help message

Example:
  $0 --org-id 123456789 --billing-account ABCDEF-123456-ABCDEF
EOF
  exit 0
}

ORG_ID=""
BILLING_ACCOUNT_ID=""

while [[ $# -gt 0 ]]; do
  case $1 in
    --org-id) ORG_ID="$2"; shift 2 ;;
    --billing-account) BILLING_ACCOUNT_ID="$2"; shift 2 ;;
    -h|--help) usage ;;
    *) echo "ERROR: Unknown argument: $1"; usage ;;
  esac
done

command -v gcloud >/dev/null || { echo "ERROR: gcloud not found"; exit 1; }
command -v openssl >/dev/null || { echo "ERROR: openssl not found"; exit 1; }
[[ -z "$ORG_ID" ]] && { echo "ERROR: --org-id is required"; usage; }
[[ -z "$BILLING_ACCOUNT_ID" ]] && { echo "ERROR: --billing-account is required"; usage; }

echo "Verifying org and billing account..."
gcloud organizations describe $ORG_ID &>/dev/null \
  || { echo "ERROR: Organization $ORG_ID not found or no access"; exit 1; }
gcloud billing accounts describe $BILLING_ACCOUNT_ID &>/dev/null \
  || { echo "ERROR: Billing account $BILLING_ACCOUNT_ID not found or no access"; exit 1; }

STATE_PROJECT_ID="platform-tf-state-$(openssl rand -hex 4)"
DEV_PROJECT_ID="platform-dev-$(openssl rand -hex 4)"
PROD_PROJECT_ID="platform-prod-$(openssl rand -hex 4)"
CURRENT_USER=$(gcloud config get-value account)

echo "[1/5] Creating projects..."
for PROJECT_ID in $STATE_PROJECT_ID $DEV_PROJECT_ID $PROD_PROJECT_ID; do
  gcloud projects create $PROJECT_ID --organization=$ORG_ID
done

echo "[2/5] Linking billing..."
for PROJECT_ID in $STATE_PROJECT_ID $DEV_PROJECT_ID $PROD_PROJECT_ID; do
  gcloud billing projects link $PROJECT_ID --billing-account=$BILLING_ACCOUNT_ID
done

echo "[3/5] Creating state bucket..."
gcloud services enable storage.googleapis.com --project=$STATE_PROJECT_ID
BUCKET_NAME="tf-state-$(openssl rand -hex 4)"
gcloud storage buckets create gs://$BUCKET_NAME \
  --project=$STATE_PROJECT_ID \
  --location=EU \
  --uniform-bucket-level-access
gcloud storage buckets update gs://$BUCKET_NAME --versioning

echo "[4/5] Creating Terraform service accounts..."
for PROJECT_ID in $DEV_PROJECT_ID $PROD_PROJECT_ID; do
  gcloud iam service-accounts create terraform \
    --display-name="Terraform" --project=$PROJECT_ID
done
sleep 10 # gcp needs some time to create account

echo "[5/5] Assigning IAM roles..."
for PROJECT_ID in $DEV_PROJECT_ID $PROD_PROJECT_ID; do
  for ROLE in roles/editor roles/iam.serviceAccountAdmin roles/resourcemanager.projectIamAdmin; do
    gcloud projects add-iam-policy-binding $PROJECT_ID \
      --member="serviceAccount:terraform@$PROJECT_ID.iam.gserviceaccount.com" \
      --role=$ROLE \
      --condition=None
  done
  # iamcredentials API is required in dev/prod projects when using a quota project with ADC
  gcloud services enable iamcredentials.googleapis.com --project=$PROJECT_ID
  gcloud storage buckets add-iam-policy-binding gs://$BUCKET_NAME \
    --member="serviceAccount:terraform@$PROJECT_ID.iam.gserviceaccount.com" \
    --role="roles/storage.objectAdmin"
done
gcloud storage buckets add-iam-policy-binding gs://$BUCKET_NAME \
    --member="user:$CURRENT_USER" \
    --role="roles/storage.objectAdmin"

echo ""
echo "Bootstrap complete."
echo ""
echo "State bucket:  $BUCKET_NAME"
echo "State project: $STATE_PROJECT_ID"
echo "Dev project:   $DEV_PROJECT_ID"
echo "Prod project:  $PROD_PROJECT_ID"
