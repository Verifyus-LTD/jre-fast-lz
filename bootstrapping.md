# Placard Media - Google Foundation Fabric (FAST) Bootstrapping & Operations Guide

This guide documents the enterprise bootstrapping architecture, user onboarding workflows, and utility scripts for the Placard Media Cloud Foundation Fabric landing zone (`/Users/jrevans/Code/placard/jre-fast-lz`).

---

## 1. Landing Zone Overview & Architecture

* **Google Cloud Organization:** `placard.media` (ID: `150829647948`)
* **GCP Billing Account:** `011375-A0472C-432D72`
* **Prefix:** `placard`
* **Primary Region:** `europe-west2` (London)
* **Secondary Region:** `europe-west1` / `us-east1`
* **Multi-Region Storage/BigQuery:** `EU`

### Core Projects

| Project ID | Role & Description |
|---|---|
| `placard-prod-iac-core-0` | **IaC Core Automation:** Hosts Terraform state buckets, stage outputs bucket, and IaC stage service accounts (`iac-org-*`, `iac-networking-*`, `iac-pf-*`, etc.). |
| `placard-prod-net-core-0` | **Network Core:** Hosts the NCC Hub, core Cloud Routers, and transit VPC (`hub-0`). |
| `placard-dev-net-spoke-0` | **Development Network Spoke:** Hosts the dev shared VPC (`dev-0`) and dev subnets. |
| `placard-prod-net-spoke-0` | **Production Network Spoke:** Hosts the prod shared VPC (`prod-0`) and prod subnets. |
| `placard-prod-audit-logs-0` | **Observability:** Centralized Cloud Logging buckets and audit log export sinks. |
| `placard-prod-billing-exp-0` | **FinOps:** BigQuery datasets for Cloud Billing export and usage reporting. |

### Canonical GCS Buckets (in `placard-prod-iac-core-0`)

* **Outputs Bucket:** `gs://placard-prod-iac-core-0-iac-outputs`
  * `/providers/`: Generated provider definitions (`0-org-setup-providers.tf`, `2-networking-providers.tf`, etc.) configured with GCS backends and Service Account impersonation.
  * `/tfvars/`: Inter-stage variable dependency JSONs (`0-globals.auto.tfvars.json`, `0-org-setup.auto.tfvars.json`, `2-networking.auto.tfvars.json`).
* **Org State Bucket:** `gs://placard-prod-iac-core-0-iac-org-state`
  * Holds Stage 0 (`0-org-setup`) state.
* **Stage State Bucket:** `gs://placard-prod-iac-core-0-iac-stage-state`
  * Holds state files for all subsequent stages (`1-vpcsc/`, `2-networking/`, `2-security/`, `2-project-factory/`).

---

## 2. Access Management: Groups vs. Direct Users

### ⚠️ The Golden Rule of FAST IAM: Never Rely on Direct User Bindings
Cloud Foundation Fabric (FAST) enforces **authoritative IAM bindings** (`google_organization_iam_binding`, `google_project_iam_binding`). 

If you grant a role directly to an individual email (e.g. `user:tessa@placard.media`) via `gcloud`, **Terraform will mark it as unmanaged drift and attempt to delete/revoke it during `terraform apply`**.

### Standard Google Groups (`admin.google.com`)
All landing zone permissions are granted to pre-defined Google Groups. To onboard an engineer, add their Google Workspace account to the relevant group:

| Google Group Email | Role in Landing Zone |
|---|---|
| `gcp-org-admins@placard.media` | **Full Infrastructure Admin:** Organization Owner, Org Admin, and Service Account Token Creator across all stage SAs. |
| `gcp-network-admins@placard.media` | **Network Engineer:** Admin access on network host projects, NCC hubs, and `iac-networking-*` impersonation. |
| `gcp-security-admins@placard.media` | **Security Engineer:** Access to KMS, VPC-SC perimeters, and `iac-security-*` impersonation. |
| `gcp-billing-admins@placard.media` | **FinOps / Billing:** Administrator on Billing Account `011375-A0472C-432D72`. |
| `gcp-devops@placard.media` | **Workload Teams:** Project Factory management and shared VPC attachment permissions. |

---

## 3. Engineer Onboarding & Bootstrapping Runbook

Follow this workflow for any new engineer or fresh Cloud Shell environment:

### Step 1: User Provisioning (Admin Action)
In the Google Workspace Admin Console ([admin.google.com](https://admin.google.com)):
1. Add the user's account (e.g. `tessa@placard.media`) to **`gcp-org-admins@placard.media`** (or the stage-specific group).
2. Ensure their GitHub account is a member of the **`Verifyus-LTD`** organization with `Write` access to the repository (`Verifyus-LTD/jre-fast-lz`).

### Step 2: Authenticate Local / Cloud Shell Environment
Both `gcloud` CLI and Terraform's Application Default Credentials (ADC) must be authenticated to the `@placard.media` identity:

```bash
# 1. Authenticate CLI
gcloud auth login

# 2. Authenticate Terraform Application Default Credentials (ADC)
gcloud auth application-default login
```

### Step 3: Lock Quota & Active Project
To prevent 403 `serviceusage.services.use` quota errors, lock the session to `placard-prod-iac-core-0`:

```bash
gcloud config set project placard-prod-iac-core-0
gcloud auth application-default set-quota-project placard-prod-iac-core-0
export GOOGLE_CLOUD_PROJECT="placard-prod-iac-core-0"
export GOOGLE_PROJECT="placard-prod-iac-core-0"
```

### Step 4: Clone & Navigate to Target Stage
Navigate to the stage you intend to execute (e.g., `2-networking` or `2-project-factory`):

```bash
cd ~/jre-fast-lz/fast/stages/2-networking
```

### Step 5: Link Stage Providers & Inputs
Run the helper script or `fast-links.sh`:

```bash
# Pull providers and variable dependencies from GCS
../fast-links.sh gs://placard-prod-iac-core-0-iac-outputs | bash
```

### Step 6: Initialize & Plan
```bash
terraform init
terraform plan
```

---

## 4. Repository Scripts Reference

### Root Directory

#### `jre.sh`
* **Path:** `/Users/jrevans/Code/placard/jre-fast-lz/jre.sh`
* **Purpose:** Initial bootstrap script for the GCP organization.
* **Key Features:**
  * Grants prerequisite organization roles (`roles/owner`, `roles/resourcemanager.organizationAdmin`, `roles/billing.admin`) to the executing principal or admin group.
  * Dynamically detects if `placard-prod-iac-core-0` exists; if so, sets it as the persistent quota project.
  * Does **not** execute any `terraform state rm` commands, ensuring core projects remain tracked in state.

---

### Stages Directory (`fast/stages/`)

#### `setup-placard-env.sh`
* **Path:** `fast/stages/setup-placard-env.sh`
* **Purpose:** Interactive onboarding tool for team members.
* **Key Features:**
  * Checks CLI prerequisites (`gcloud`, `terraform`).
  * Validates that the active `gcloud` account belongs to `@placard.media`.
  * **ADC Verification:** Inspects the current ADC token. If the ADC token belongs to a different Google account, automatically triggers `gcloud auth application-default login` to prevent authentication drift.
  * Sets quota project to `placard-prod-iac-core-0`.
  * Verifies Service Account Impersonation against the selected stage (`iac-*-ro`).
  * Verifies read access to `gs://placard-prod-iac-core-0-iac-outputs`.

#### `fast-links.sh`
* **Path:** `fast/stages/fast-links.sh`
* **Purpose:** Canonical FAST utility to link provider files and dependency tfvars.
* **Usage:** `../fast-links.sh gs://placard-prod-iac-core-0-iac-outputs | bash`
* **Key Features:**
  * Pulls `providers/${STAGE}-providers.tf` into `./providers.tf`.
  * Pulls required dependencies listed in `.fast-stage.env` (`FAST_STAGE_DEPS`).
  * Handles optional files (`FAST_STAGE_OPTIONAL`) gracefully with `2>/dev/null || true` to prevent false-alarm `ERROR: matched no objects` errors in terminal pipelines.

#### `perm.sh`
* **Path:** `fast/stages/perm.sh`
* **Purpose:** Automated IAM remediation script for foundation and user onboarding.
* **Key Features:**
  * **Organization-Wide Quota Role:** Grants `roles/serviceusage.serviceUsageConsumer` at the **Organization Level** (`150829647948`) to all stage service accounts (`iac-org-*`, `iac-networking-*`, `iac-pf-*`, `iac-security-*`, `iac-vpcsc-*`). This ensures that no matter what active project an engineer's Cloud Shell is set to, GCS state backend queries will never fail with 403.
  * **Stage 0 SAs:** Ensures `iac-org-rw` has core management roles on `placard-prod-iac-core-0`.
  * **Engineer Access:** Grants `roles/iam.serviceAccountTokenCreator`, `roles/viewer`, and `roles/storage.objectViewer` to onboarding users (`tessa@placard.media`).
  * **Safe & Idempotent:** Contains zero `rm` or `state rm` operations. Safe to run at any time.

---

### Stage-Specific Scripts

#### `2-networking/rmefirst.sh`
* **Path:** `fast/stages/2-networking/rmefirst.sh`
* **Purpose:** Prepares Stage 2 Networking workspace.
* **Key Features:**
  * Cleans up stale local provider symlinks.
  * Directly downloads `2-networking-providers.tf`, `0-globals.auto.tfvars.json`, and `0-org-setup.auto.tfvars.json` from `gs://placard-prod-iac-core-0-iac-outputs`.
  * Configures `2-networking.auto.tfvars` to target the NCC Hub-and-Spoke dataset (`datasets/hub-and-spokes-ncc`).

#### `2-networking/gcloud-fix.sh`
* **Path:** `fast/stages/2-networking/gcloud-fix.sh`
* **Purpose:** Fixes API service enablement and imports networking projects into state.
* **Key Features:**
  * Enables `logging.googleapis.com` on `placard-prod-net-core-0`, `placard-prod-net-spoke-0`, and `placard-dev-net-spoke-0`.
  * Safely imports the 3 networking projects (`net-core-0`, `net-dev-0`, `net-prod-0`) into Terraform state if they are missing.
  * Does **not** run `terraform state rm` on project resources.

#### `2-project-factory/rmefirst.sh`
* **Path:** `fast/stages/2-project-factory/rmefirst.sh`
* **Purpose:** Prepares Stage 2 Project Factory workspace.
* **Key Features:**
  * Downloads `2-project-factory-providers.tf` and Stage 0 variables from GCS.
  * Downloads `2-networking.auto.tfvars.json`, which populates `host_project_ids` so that Shared VPC variables (`$project_ids:net-dev-0`, `$project_ids:net-prod-0`) resolve cleanly to their real project IDs.

---

## 5. Troubleshooting & Common Errors

### 1. `Error 403: iac-*-rw does not have serviceusage.services.use access`
* **Cause:** The GCS backend client is sending a quota project where the service account does not have permission, or Cloud Shell is defaulted to a non-IaC project.
* **Remediation:**
  1. Run `fast/stages/perm.sh` from an admin session (grants the role organization-wide).
  2. In the engineer's terminal, run:
     ```bash
     gcloud config set project placard-prod-iac-core-0
     export GOOGLE_CLOUD_PROJECT="placard-prod-iac-core-0"
     ```

### 2. `Error: Duplicate 'backend' configuration block`
* **Cause:** Both `providers.tf` and a stage-named provider file (e.g. `2-networking-providers.tf`) are present in the folder.
* **Remediation:** Delete the duplicate `providers.tf`:
  ```bash
  rm providers.tf
  terraform init
  ```

### 3. `Plan shows: 22 to destroy` (Service Agents)
* **Cause:** The parent `google_project` resources were removed from Terraform state, causing Terraform to plan project recreation with `(known after apply)` project numbers.
* **Remediation:** Import the existing projects back into state:
  ```bash
  terraform import 'module.projects.module.projects["net-core-0"].google_project.project[0]' placard-prod-net-core-0
  terraform import 'module.projects.module.projects["net-dev-0"].google_project.project[0]' placard-dev-net-spoke-0
  terraform import 'module.projects.module.projects["net-prod-0"].google_project.project[0]' placard-prod-net-spoke-0
  ```

### 4. `+ host_project = "$project_ids:net-dev-0"` in Project Factory Plan
* **Cause:** `2-networking.auto.tfvars.json` is missing from the `2-project-factory` directory, leaving the symbolic context variable unresolved.
* **Remediation:** Pull the networking outputs file:
  ```bash
  gcloud storage cp gs://placard-prod-iac-core-0-iac-outputs/tfvars/2-networking.auto.tfvars.json ./
  terraform plan
  ```

### 5. `dial tcp ...:443: connect: connection refused`
* **Cause:** Local macOS network extension (e.g. Little Snitch Mini) is intercepting outbound API calls from `terraform-provider-google` and resetting the connection.
* **Remediation:**
  1. Add an allow rule in Little Snitch Mini for `terraform` and `terraform-provider-*` to connect to `*.googleapis.com`.
  2. Ensure unnecessary BigQuery APIs are removed from non-BigQuery project definitions (e.g., `iac-0.yaml`).

### 6. GitHub PR Permission Denied on `main`
* **Cause:** Direct pushes to `main` are blocked by branch protection, and `.github/CODEOWNERS` does not grant repository push rights.
* **Remediation:**
  1. Ensure the user's GitHub account has `Write` permissions in `Verifyus-LTD/jre-fast-lz`.
  2. Push to a feature branch:
     ```bash
     git checkout -b <username>/<feature-name>
     git push -u origin <username>/<feature-name>
     ```
  3. Open a Pull Request on GitHub against `main`.
