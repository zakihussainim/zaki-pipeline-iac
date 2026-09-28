module "s3_buckets" {
  source = "../../modules/s3-buckets"

  project_prefix = "zaki-pipeline-iac-dev"
}

module "glue_pipeline" {
  source = "../../modules/glue-pipeline"

  project_prefix      = "zaki-pipeline-iac-dev"
  alert_email         = var.alert_email
  raw_bucket_name     = module.s3_buckets.raw_bucket_name
  raw_bucket_arn      = module.s3_buckets.raw_bucket_arn
  curated_bucket_name = module.s3_buckets.curated_bucket_name
  curated_bucket_arn  = module.s3_buckets.curated_bucket_arn
  scripts_bucket_name = module.s3_buckets.scripts_bucket_name
  scripts_bucket_arn  = module.s3_buckets.scripts_bucket_arn
}

module "glue_catalog" {
  source = "../../modules/glue-catalog"

  project_prefix      = "zaki-pipeline-iac-dev"
  curated_bucket_name = module.s3_buckets.curated_bucket_name
  curated_bucket_arn  = module.s3_buckets.curated_bucket_arn

}