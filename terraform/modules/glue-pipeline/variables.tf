variable "project_prefix" {
  description = "Prefix used for resource names, e.g. zaki-pipeline-iac-dev"
  type        = string
}

variable "alert_email" {
  description = "Email address for SNS data-quality alerts"
  type        = string
}

variable "raw_bucket_name" {
  type = string
}

variable "raw_bucket_arn" {
  type = string
}

variable "curated_bucket_name" {
  type = string
}

variable "curated_bucket_arn" {
  type = string
}

variable "scripts_bucket_name" {
  type = string
}

variable "scripts_bucket_arn" {
  type = string
}