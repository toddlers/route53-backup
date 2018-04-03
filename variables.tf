variable "aws_region" {
  default = "us-east-1"
}

variable "r53_backup_bucket_arn" {
  default = "arn:aws:s3:::backup-stuff"
}

variable "r53_backup_bucket_name" {
  default = "backup-stuff"
}
