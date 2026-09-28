output "glue_job_name" {
  value = aws_glue_job.clean_sales_transactions.name
}

output "glue_role_arn" {
  value = aws_iam_role.glue.arn
}

output "sns_topic_arn" {
  value = aws_sns_topic.alerts.arn
}