# Sales Transactions Data Pipeline — Terraform + CI/CD

An AWS data pipeline that ingests raw sales transaction data, validates and
cleans it, and makes it queryable — all infrastructure defined in Terraform
and deployed automatically through GitHub Actions.


## The problem

Sales transaction records arrive as CSV files with inconsistent quality:
mixed date formats, missing customer or order IDs, non-positive quantities
or prices, invalid currency codes, and duplicate orders. Downstream
consumers (analysts querying via Athena) need clean, structured data — not
raw exports — and bad records need to be visible rather than silently
dropped or silently corrupted.

Constraints:
- Data volume: batch, not streaming (~800 records per run in this build;
  designed to scale to larger batch sizes without code changes)
- Latency: not time-critical — a daily or on-demand batch job is sufficient
- Consumers: analysts querying the curated data through Athena/Glue
  Data Catalog
- No AWS account IDs or personal details may appear in files committed to
  the (public) GitHub repo

## Architecture

![Architecture diagram: CSV upload lands in the S3 raw bucket; a Glue PySpark job cleans, dedupes and validates it, writing clean partitioned Parquet to the curated bucket and bad records to quarantine, and sends data-quality alerts via SNS email; a Glue Crawler catalogs the curated data for Athena SQL queries](architecture.png)

Deployment path:

![Deployment path: a git push triggers the GitHub Actions lint job (terraform fmt -check, validate, tflint); apply-dev then deploys to dev automatically via OIDC, while apply-prod waits for manual approval on a GitHub Environment before deploying to prod](deployment-path.png)

All AWS access from CI uses OIDC federation — no long-lived AWS access keys
are stored in GitHub at any point.

## Alternatives considered

**IAM permissions: broad role vs. per-resource least privilege.**
Chose a dedicated least-privilege IAM policy for the CI/CD deploy role,
scoped to this project's resources by ARN prefix (e.g.
`arn:aws:iam::<account>:role/zaki-pipeline-iac-*`), built by starting from a
reasonably scoped baseline and adding exactly the actions that real
`AccessDenied` errors revealed were missing. A wildcard `"*"`-resource
admin-style role would have been faster to write but defeats the purpose of
a least-privilege exercise and is a bigger blast radius if the role or its
credentials were ever compromised.

**Manual approval gate: dev and prod, or prod only.**
Chose to gate only the prod deployment behind manual approval, with dev
deploying automatically on every push to `main`. Gating both would slow
down iteration on a project with no real production traffic; gating neither
would remove the safety check that matters most — deploying to the
environment other people might actually rely on.

**Data Catalog: manually defined table vs. Glue Crawler.**
Chose a Glue Crawler that auto-discovers the schema and Hive-style
partitions (`order_year`, `order_month`, `region`) from the curated Parquet
output. A manually defined Catalog table is more predictable but has to be
kept in sync by hand every time the schema changes; the crawler re-syncs
itself on each run at the cost of a short discovery pass.

**Terraform state: single shared state file vs. per-environment.**
Chose separate state files per environment (`dev/terraform.tfstate`,
`prod/terraform.tfstate`) in the same S3 bucket, so a bug or bad apply in
dev cannot corrupt or lock prod state. State locking uses Terraform's
native S3 locking (`use_lockfile = true`, requires Terraform ≥1.10) rather
than a separate DynamoDB lock table, since native locking removes the extra
resource to manage without losing the safety guarantee.

## What broke during testing (and how it was fixed)

- **Silent partition corruption from a mixed date format.** Some rows'
  `order_date` was `dd/MM/yyyy` while others were `yyyy-MM-dd`. Spark's
  `inferSchema` read the column as a string, so `F.year()`/`F.month()`
  returned null for the rows in the "wrong" format — with no error, no job
  failure, just missing partition data. Fixed by parsing both formats
  explicitly with `F.coalesce(F.to_date(col, "yyyy-MM-dd"), F.to_date(col,
  "dd/MM/yyyy"))` and adding an explicit data-quality check for
  unparseable dates, so a genuinely bad row is quarantined and visible
  instead of silently dropped from a partition.


- **GitHub's OIDC subject-claim change (July 2026).** Repos created after
  this date get an immutable, ID-based `sub` claim
  (`repo:OWNER@OWNER-ID/REPO@REPO-ID:ref:...`) instead of the older
  name-based format. The IAM trust policy's `StringLike` condition now
  accepts both formats, so the role trust doesn't silently break if the
  repo is ever renamed or transferred.

- **Multiple rounds of `AccessDenied` in CI.** The CI role's permissions
  policy was missing several actions the deploy actually needed
  (`glue:GetTags`, `sns:ListTagsForResource`, `s3:GetBucketPolicy`,
  `s3:GetBucketAcl`, `sns:GetSubscriptionAttributes`,
  `s3:GetBucketCORS`, among others). Each was found by reading the exact
  `AccessDenied` error from a failed `terraform apply` run and adding
  precisely that action — never a broader wildcard — until a clean apply
  succeeded.

- **`terraform fmt` and TFLint failures in CI.** Formatting and linting
  are enforced in the `lint` job. Fixed by running `terraform fmt
  -recursive terraform/` locally before every commit, and adding the
  standard `required_version`/`required_providers` block to each module
  that TFLint flagged as missing one.

## How to run it

### Prerequisites

- An AWS account
- [Terraform](https://developer.hashicorp.com/terraform) >= 1.10.0
- A GitHub repository with:
  - An AWS IAM OIDC identity provider trusting
    `token.actions.githubusercontent.com` (created once via the
    `terraform/bootstrap` configuration)
  - Repository **secrets**: `TFSTATE_BUCKET`, `ALERT_EMAIL`,
    `AWS_ROLE_ARN`
  - A `production` GitHub Environment with a required reviewer, for the
    manual approval gate on prod deploys

### One-time bootstrap

The `terraform/bootstrap` module creates the shared, account-level
resources every environment depends on: the S3 bucket used for Terraform
state, the GitHub OIDC provider, and the least-privilege IAM role GitHub
Actions assumes to deploy. This is applied once, locally, by whoever sets
the project up — not by CI.

### Deploying dev and prod

1. Push a change to a branch and open a pull request — the `lint` and
   `plan-dev` jobs run automatically and show the planned changes.
2. Merge to `main` — `apply-dev` runs automatically.
3. `apply-prod` then waits for manual approval in the `production` GitHub
   Environment before applying the same changes to the prod environment.

Each environment (`terraform/envs/dev`, `terraform/envs/prod`) has its own
Terraform state file in the same state-storage S3 bucket, so a dev deploy
can never affect prod resources.

### Running locally

```
cd terraform/envs/dev
terraform init -backend-config="backend.hcl"
terraform plan
```

`backend.hcl` and `terraform.tfvars` are gitignored — each environment
needs its own local copies (see `variables.tf` for the variables each one
requires) since they're never committed to the repo.
