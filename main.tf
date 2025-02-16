resource "random_pet" "this" {}

data "cloudflare_zone" "this" {
  filter = {
    name = var.domain
  }
}

resource "aws_acm_certificate" "this" {
  domain_name       = var.domain
  validation_method = "DNS"

  subject_alternative_names = ["www.${var.domain}"]
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
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }
    effect    = "Allow"
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
  name    = "AppendIndex-${random_pet.this.id}"
  runtime = "cloudfront-js-1.0"
  comment = "Appends index.html to folder requests"
  code    = file("${path.module}/resources/implicit-index-html/handler.js")
}

data "aws_api_gateway_rest_api" "contact" {
  name = "ContactFormAPI"
}

resource "aws_apigatewayv2_domain_name" "this" {
  domain_name = var.domain

  domain_name_configuration {
    certificate_arn = aws_acm_certificate.this.arn
    endpoint_type   = "REGIONAL"
    security_policy = "TLS_1_2"
  }
}

resource "aws_apigatewayv2_api_mapping" "this" {
  api_id      = data.aws_api_gateway_rest_api.contact.id
  domain_name = aws_apigatewayv2_domain_name.this.id
  stage       = "prod"
}

data "aws_cloudfront_cache_policy" "caching_disabled" {
  name = "Managed-CachingDisabled"
}

data "aws_cloudfront_origin_request_policy" "user_agent_referer" {
  name = "Managed-UserAgentRefererHeaders"
}



resource "aws_cloudfront_distribution" "this" {
  origin {
    origin_id                = random_pet.this.id
    origin_access_control_id = aws_cloudfront_origin_access_control.this.id
    domain_name              = aws_s3_bucket.this.bucket_regional_domain_name
  }

  origin {
    origin_id   = "${data.aws_api_gateway_rest_api.contact.id}.execute-api.${data.aws_region.current.name}.amazonaws.com"
    origin_path = "/prod"
    domain_name = "${data.aws_api_gateway_rest_api.contact.id}.execute-api.${data.aws_region.current.name}.amazonaws.com"

    custom_origin_config {
      origin_protocol_policy = "https-only"
      origin_ssl_protocols   = ["TLSv1.2"]
      http_port              = 80
      https_port             = 443
    }

    custom_header {
      name = "CfDomain"
      value = var.domain
    }
  }

  enabled             = true
  is_ipv6_enabled     = true
  comment             = var.domain
  default_root_object = "index.html"

  aliases = [var.domain, "www.${var.domain}"]

  default_cache_behavior {
    allowed_methods = ["GET", "HEAD", "OPTIONS"]
    cached_methods  = ["GET", "HEAD"]
    compress        = true

    cache_policy_id  = "658327ea-f89d-4fab-a63d-7e88639e58f6"
    target_origin_id = random_pet.this.id

    viewer_protocol_policy = "redirect-to-https"

    function_association {
      event_type   = "viewer-request"
      function_arn = aws_cloudfront_function.this.arn
    }
  }

  ordered_cache_behavior {
    path_pattern     = "/submit"
    allowed_methods  = ["HEAD", "DELETE", "POST", "GET", "OPTIONS", "PUT", "PATCH"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "${data.aws_api_gateway_rest_api.contact.id}.execute-api.${data.aws_region.current.name}.amazonaws.com"

    viewer_protocol_policy = "redirect-to-https"
    compress               = true

    cache_policy_id = data.aws_cloudfront_cache_policy.caching_disabled.id
    origin_request_policy_id = data.aws_cloudfront_origin_request_policy.user_agent_referer.id
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
