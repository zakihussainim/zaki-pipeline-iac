output "raw_bucket_name" {
  value = aws_s3_bucket.raw.id
}

output "raw_bucket_arn" {
  value = aws_s3_bucket.raw.arn
}

output "curated_bucket_name" {
  value = aws_s3_bucket.curated.id
}

output "curated_bucket_arn" {
  value = aws_s3_bucket.curated.arn
}

output "scripts_bucket_name" {
  value = aws_s3_bucket.scripts.id
}

output "scripts_bucket_arn" {
  value = aws_s3_bucket.scripts.arn
}

output "athena_bucket_name" {
  value = aws_s3_bucket.athena.id
}

output "athena_bucket_arn" {
  value = aws_s3_bucket.athena.arn
}