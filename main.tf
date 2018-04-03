provider "aws" {
  region = "${var.aws_region}"
}

resource "aws_cloudwatch_event_rule" "r53-backup-event" {
  name                = "r53-backup-event"
  description         = "backup route53 zone"
  schedule_expression = "cron(0 02 * * ? *)"
}

resource "aws_cloudwatch_event_target" "check-file-event-lambda-target" {
  target_id = "check-file-event-lambda-target"
  rule      = "${aws_cloudwatch_event_rule.r53-backup-event.name}"
  arn       = "${aws_lambda_function.route53_backup_lambda.arn}"
  input = <<EOF
{
  "bucket_name": "${var.r53_backup_bucket_name}"
}
EOF
}

resource "aws_iam_role" "r53_backup_lambda" {
    name = "r53_backup_lambda"
    assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF
}

data "aws_iam_policy_document" "route53-backup-access-ro" {
  statement {
    actions = [
      "route53:Get*",
      "route53:List*",
    ]
    resources = [
      "*",
    ]
  }
}

data "aws_iam_policy_document" "route53-backup-s3-access" {
  statement {
    actions = [
      "s3:PutObject"
    ]
    resources = [
      "${var.r53_backup_bucket_arn}",
      "${var.r53_backup_bucket_arn}/*"
    ]
  }
}

resource "aws_iam_policy" "route53-backup-access-ro" {
  name    = "route53-backup-access-ro"
  path    = "/"
  policy  = "${data.aws_iam_policy_document.route53-backup-access-ro.json}"
}

resource "aws_iam_policy" "route53-backup-s3-access" {
  name    = "route53-backup-s3-access"
  path    = "/"
  policy  = "${data.aws_iam_policy_document.route53-backup-s3-access.json}"
}

resource "aws_iam_role_policy_attachment" "route53-backup-access-ro" {
  role       = "${aws_iam_role.r53_backup_lambda.name}"
  policy_arn = "${aws_iam_policy.route53-backup-access-ro.arn}"
}

resource "aws_iam_role_policy_attachment" "route53-backup-s3-access" {
  role       = "${aws_iam_role.r53_backup_lambda.name}"
  policy_arn = "${aws_iam_policy.route53-backup-s3-access.arn}"
}

resource "aws_iam_role_policy_attachment" "basic-exec-role" {
  role       = "${aws_iam_role.r53_backup_lambda.name}"
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_lambda_permission" "allow_cloudwatch_to_call_check_file" {
  statement_id  = "AllowExecutionFromCloudWatch"
  action        = "lambda:InvokeFunction"
  function_name = "${aws_lambda_function.route53_backup_lambda.function_name}"
  principal     = "events.amazonaws.com"
  source_arn    = "${aws_cloudwatch_event_rule.r53-backup-event.arn}"
}

resource "aws_lambda_function" "route53_backup_lambda" {
  filename      = "route53_backup_lambda.zip"
  function_name = "route53_backup"
  description   = "backup route53"
  role          = "${aws_iam_role.r53_backup_lambda.arn}"
  handler       = "route53_backup.handler"
  runtime       = "python2.7"
  timeout       = 30
  source_code_hash = "${base64sha256(file("route53_backup_lambda.zip"))}"
}
