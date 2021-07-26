resource "aws_s3_bucket" "website" {
  bucket_prefix = "${local.prefix}-website"
  acl           = "private"
}

resource "aws_s3_bucket_policy" "website" {
  bucket = aws_s3_bucket.website.id
  policy = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "AWS": "${aws_cloudfront_origin_access_identity.website.iam_arn}"
            },
            "Action": "s3:GetObject",
            "Resource": "${aws_s3_bucket.website.arn}/*"
        },
        {
            "Effect": "Allow",
            "Principal": {
                "AWS": "${aws_cloudfront_origin_access_identity.website.iam_arn}"
            },
            "Action": "s3:ListBucket",
            "Resource": "${aws_s3_bucket.website.arn}"
        }
    ]
}
EOF
}

resource "aws_cloudfront_origin_access_identity" "website" {
  comment = "${local.prefix}-website"
}

resource "aws_cloudfront_distribution" "website" {
  origin {
    domain_name = aws_s3_bucket.website.bucket_regional_domain_name
    origin_id   = aws_cloudfront_origin_access_identity.website.id

    s3_origin_config {
      origin_access_identity = aws_cloudfront_origin_access_identity.website.cloudfront_access_identity_path
    }
  }

  enabled         = true
  is_ipv6_enabled = true

  default_root_object = local.website.index_file
  custom_error_response {
    error_code         = 404
    response_code      = 404
    response_page_path = "/${local.website.error_file}"
  }

  aliases = [
    local.domain_website,
    "www.${local.domain_website}"
  ]

  #TODO
  price_class = "PriceClass_100"

  viewer_certificate {
    acm_certificate_arn      = aws_acm_certificate.website.arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }

  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD", "OPTIONS"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = aws_cloudfront_origin_access_identity.website.id

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }

    function_association {
      event_type   = "viewer-request"
      function_arn = aws_cloudfront_function.redirect_function.arn
    }

    compress               = true
    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  wait_for_deployment = true
}

resource "aws_cloudfront_function" "redirect_function" {
  name    = "${local.prefix}-redirect"
  runtime = "cloudfront-js-1.0"
  comment = "redirect all subdomains to ${local.domain_website}"
  publish = true
  code    = <<EOF
function handler(event) {
  var request = event.request;
  var uri = request.uri;
  var host = request.headers.host.value;
  var newurl = "https://" + "${local.domain_website}" + uri;

  if (host !== "${local.domain_website}") {
    var response = {
      statusCode: 302,
      statusDescription: 'Found',
      headers:
        { "location": { "value": newurl } }
    }

    return response;
  }

  return request;
}
EOF
}

resource "aws_route53_record" "website" {
  name    = local.domain_website
  type    = "A"
  zone_id = data.aws_route53_zone.domain.zone_id
  alias {
    evaluate_target_health = false
    name                   = aws_cloudfront_distribution.website.domain_name
    zone_id                = aws_cloudfront_distribution.website.hosted_zone_id
  }
}

resource "aws_route53_record" "website_www" {
  name    = "www.${local.domain_website}"
  type    = "A"
  zone_id = data.aws_route53_zone.domain.zone_id
  alias {
    evaluate_target_health = false
    name                   = aws_cloudfront_distribution.website.domain_name
    zone_id                = aws_cloudfront_distribution.website.hosted_zone_id
  }
}

resource "aws_s3_bucket_object" "website" {
  for_each = fileset(local.website.source_dir, "*")

  bucket = aws_s3_bucket.website.bucket
  key    = each.key
  source = "${local.website.source_dir}/${each.key}"
  etag   = filemd5("${local.website.source_dir}/${each.key}")

  cache_control = length(local.website.cache_files_regex) > 0 && length(regexall(local.website.cache_files_regex, each.key)) > 0 ? "max-age=${local.website.cache_files_max_age}" : "no-cache"
  content_type  = lookup(local.content_type_map, regex("\\.(?P<extension>[A-Za-z0-9.]+)$", each.key).extension, null)
}

resource "aws_s3_bucket_object" "config_file" {
  bucket  = aws_s3_bucket.website.bucket
  key     = "app_config.js"
  content = local.app_config_js

  cache_control = "no-cache"
  content_type  = "application/javascript"
}

resource "local_file" "config_file" {
  filename = "${path.module}/serve/app_config.js"
  content  = local.app_config_js
}
