resource "aws_sns_topic" "alerts" {
  name = "${var.project_prefix}-alerts"
}

resource "aws_sns_topic_subscription" "alerts_email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

data "aws_iam_policy_document" "glue_trust" {
  statement {
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["glue.amazonaws.com"]
    }
    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "glue" {
  name               = "${var.project_prefix}-glue-role"
  assume_role_policy = data.aws_iam_policy_document.glue_trust.json
}

data "aws_iam_policy_document" "glue_permissions" {
  statement {
    sid     = "ReadRawAndScript"
    effect  = "Allow"
    actions = ["s3:GetObject"]
    resources = [
      "${var.raw_bucket_arn}/*",
      "${var.scripts_bucket_arn}/*",
    ]
  }

  statement {
    sid     = "ReadWriteCurated"
    effect  = "Allow"
    actions = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject", "s3:ListBucket"]
    resources = [
      var.curated_bucket_arn,
      "${var.curated_bucket_arn}/*",
    ]
  }

  statement {
    sid       = "PublishAlerts"
    effect    = "Allow"
    actions   = ["sns:Publish"]
    resources = [aws_sns_topic.alerts.arn]
  }

  statement {
    sid       = "GlueLogging"
    effect    = "Allow"
    actions   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["arn:aws:logs:*:*:log-group:/aws-glue/*"]
  }
}

resource "aws_iam_role_policy" "glue_permissions" {
  name   = "${var.project_prefix}-glue-permissions"
  role   = aws_iam_role.glue.id
  policy = data.aws_iam_policy_document.glue_permissions.json
}

resource "aws_glue_job" "clean_sales_transactions" {
  name     = "${var.project_prefix}-clean-sales-transactions"
  role_arn = aws_iam_role.glue.arn

  command {
    name            = "glueetl"
    script_location = "s3://${var.scripts_bucket_name}/clean_sales_transactions.py"
    python_version  = "3"
  }

  default_arguments = {
    "--RAW_PATH"        = "s3://${var.raw_bucket_name}/sales_transactions_raw.csv"
    "--CURATED_PATH"    = "s3://${var.curated_bucket_name}/data/"
    "--QUARANTINE_PATH" = "s3://${var.curated_bucket_name}/quarantine/"
    "--SNS_TOPIC_ARN"   = aws_sns_topic.alerts.arn
  }

  glue_version      = "4.0"
  number_of_workers = 2
  worker_type       = "G.1X"
}

