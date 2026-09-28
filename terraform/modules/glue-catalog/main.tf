terraform {
  required_version = ">= 1.10.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

resource "aws_glue_catalog_database" "this" {
  name = "${var.project_prefix}-catalog"
}

data "aws_iam_policy_document" "crawler_trust" {
  statement {
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["glue.amazonaws.com"]
    }
    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "crawler" {
  name               = "${var.project_prefix}-crawler-role"
  assume_role_policy = data.aws_iam_policy_document.crawler_trust.json
}

data "aws_iam_policy_document" "crawler_permissions" {
  statement {
    sid     = "ReadCuratedData"
    effect  = "Allow"
    actions = ["s3:GetObject", "s3:ListBucket"]
    resources = [
      var.curated_bucket_arn,
      "${var.curated_bucket_arn}/*",
    ]
  }

  statement {
    sid    = "GlueCatalogWrite"
    effect = "Allow"
    actions = [
      "glue:GetDatabase",
      "glue:GetTable",
      "glue:GetTables",
      "glue:CreateTable",
      "glue:UpdateTable",
      "glue:GetPartition",
      "glue:GetPartitions",
      "glue:BatchGetPartition",
      "glue:BatchCreatePartition",
      "glue:UpdatePartition",
    ]
    resources = ["*"]
  }

  statement {
    sid       = "CrawlerLogging"
    effect    = "Allow"
    actions   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["arn:aws:logs:*:*:log-group:/aws-glue/crawlers/*"]
  }
}

resource "aws_iam_role_policy" "crawler_permissions" {
  name   = "${var.project_prefix}-crawler-permissions"
  role   = aws_iam_role.crawler.id
  policy = data.aws_iam_policy_document.crawler_permissions.json
}

resource "aws_glue_crawler" "sales_transactions" {
  name          = "${var.project_prefix}-sales-transactions-crawler"
  role          = aws_iam_role.crawler.arn
  database_name = aws_glue_catalog_database.this.name

  s3_target {
    path = "s3://${var.curated_bucket_name}/data/"
  }
}