output "database_name" {
  value = aws_glue_catalog_database.this.name
}

output "crawler_name" {
  value = aws_glue_crawler.sales_transactions.name
}