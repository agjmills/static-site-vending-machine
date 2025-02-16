data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

data "aws_secretsmanager_secret" "cloudflare_api_token" {
  name = "cloudflare_api_token"

  provider = aws.aws_euw2
}

data "aws_secretsmanager_secret_version" "cloudflare_api_token" {
  secret_id = data.aws_secretsmanager_secret.cloudflare_api_token.id

  provider = aws.aws_euw2
}
