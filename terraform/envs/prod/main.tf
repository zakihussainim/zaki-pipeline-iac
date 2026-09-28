module "s3_buckets" {
  source = "../../modules/s3-buckets"

  project_prefix = "zaki-pipeline-iac-prod"
}