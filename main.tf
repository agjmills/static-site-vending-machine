resource "random_pet" "this" {}

data "cloudflare_zone" "this" {
  filter = {
    name = var.domain
  }
}

resource "aws_acm_certificate" "this" {
  domain_name       = var.domain
  validation_method = "DNS"

}

resource "cloudflare_dns_record" "validation" {
  for_each = {
    for dvo in aws_acm_certificate.this.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  zone_id = data.cloudflare_zone.this.id

  content = each.value.record
  name    = each.value.name
  proxied = false
  ttl     = 300
  type    = "CNAME"
}

resource "aws_s3_bucket" "this" {
  bucket = "${var.domain}-${random_pet.this.id}"

  force_destroy = true
}

resource "aws_s3_bucket_policy" "this" {
  bucket = aws_s3_bucket.this.id
  policy = data.aws_iam_policy_document.bucket_policy.json
}

data "aws_iam_policy_document" "bucket_policy" {
  statement {
    sid = "AllowCloudFrontServicePrincipalReadOnly"

    principals {
      type = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }
    effect = "Allow"
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.this.arn}/*"]

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceARN"
      values   = [aws_cloudfront_distribution.this.arn]
    }
  }
}

resource "aws_s3_bucket_website_configuration" "this" {
  bucket = aws_s3_bucket.this.id

  index_document {
    suffix = "index.html"
  }
}

resource "aws_cloudfront_origin_access_control" "this" {
  name                              = "s3-${var.domain}"
  description                       = "S3"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_function" "this" {
  name = "AppendIndex-${random_pet.this.id}"
  runtime = "cloudfront-js-1.0"
  comment = "Appends index.html to folder requests"
  code = file("${path.module}/resources/implicit-index-html/handler.js")
}


resource "aws_cloudfront_distribution" "this" {
  origin {
    origin_id                = random_pet.this.id
    origin_access_control_id = aws_cloudfront_origin_access_control.this.id
    domain_name              = aws_s3_bucket.this.bucket_regional_domain_name
  }

  enabled             = true
  is_ipv6_enabled     = true
  comment             = var.domain
  default_root_object = "index.html"

  aliases = [var.domain]

  default_cache_behavior {
    allowed_methods = ["GET", "HEAD", "OPTIONS"]
    cached_methods  = ["GET", "HEAD"]
    compress        = true

    cache_policy_id  = "658327ea-f89d-4fab-a63d-7e88639e58f6"
    target_origin_id = random_pet.this.id

    viewer_protocol_policy = "redirect-to-https"

    function_association {
      event_type = "viewer-request"
      function_arn = aws_cloudfront_function.this.arn
    }
  }

  price_class = "PriceClass_100"

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  tags = {
    Environment = "production"
  }

  viewer_certificate {
    acm_certificate_arn      = aws_acm_certificate.this.arn
    ssl_support_method       = "sni-only"     # or "vip", depending on your needs
    minimum_protocol_version = "TLSv1.2_2021" # Optional, but recommended
  }
}

resource "cloudflare_dns_record" "this" {
  zone_id = data.cloudflare_zone.this.id
  content = aws_cloudfront_distribution.this.domain_name
  name    = data.cloudflare_zone.this.name
  proxied = false
  ttl     = 1
  type    = "CNAME"
}

resource "cloudflare_dns_record" "www" {
  zone_id = data.cloudflare_zone.this.id
  content = aws_cloudfront_distribution.this.domain_name
  name    = "www.${data.cloudflare_zone.this.name}"
  proxied = false
  ttl     = 300
  type    = "CNAME"
}

resource "aws_ses_domain_identity" "this" {
  domain = var.domain
}

resource "aws_ses_domain_dkim" "this" {
  domain = aws_ses_domain_identity.this.domain
}

resource "cloudflare_dns_record" "dkim" {
  count = 3
  
  zone_id = data.cloudflare_zone.this.id
  content = "${aws_ses_domain_dkim.this.dkim_tokens[count.index]}.dkim.amazonses.com"
  name    = "${aws_ses_domain_dkim.this.dkim_tokens[count.index]}._domainkey"
  proxied = false
  ttl     = 600
  type    = "CNAME"
}

resource "aws_iam_role" "email_lambda_role" {
  name               = "${var.domain}-email-lambda"
  assume_role_policy = data.aws_iam_policy_document.email_lambda_role_policy.json
}

data "aws_iam_policy_document" "email_lambda_role_policy" {
  statement {
    principals {
      type = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
    actions = [ "sts:AssumeRole" ]
    effect = "Allow"
  }
}

resource "aws_iam_policy" "ses_send_email" {
  name        = "SES_Send_Email_Policy"
  description = "Policy to allow Lambda to send emails via SES"
  policy      = data.aws_iam_policy_document.send_ses.json
}

data "aws_iam_policy_document" "send_ses" {
  statement {
    effect = "Allow"
    actions = [ "ses:SendEmail" ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy_attachment" "lambda_ses_policy_attachment" {
  policy_arn = aws_iam_policy.ses_send_email.arn
  role       = aws_iam_role.email_lambda_role.name
}

