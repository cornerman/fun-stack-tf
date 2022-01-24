module "http" {
  count  = local.http == null ? 0 : 1
  source = "./http"

  prefix         = local.prefix
  domain         = local.domain_http
  allow_origins  = local.http.cors_protected ? local.redirect_urls : null
  hosted_zone_id = concat(data.aws_route53_zone.domain[*].zone_id, [null])[0]
  auth_module    = concat(module.auth, [null])[0]

  source_dir    = local.http.source_dir
  source_bucket = local.http.source_bucket
  timeout       = local.http.timeout
  memory_size   = local.http.memory_size
  runtime       = local.http.runtime
  handler       = local.http.handler

  environment = module.ws == null ? local.http.environment : merge(local.http.environment == null ? {} : local.http.environment, {
    FUN_WEBSOCKET_CONNECTIONS_DYNAMODB_TABLE = module.ws[0].connections_table
  })

  providers = {
    aws    = aws
    aws.us = aws.us
  }
}

resource "aws_iam_role_policy_attachment" "lambda_http_ws_connections" {
  count      = module.ws == null || module.http == null ? 0 : 1
  role       = module.http[0].http_role.name
  policy_arn = module.ws[0].connections_policy_arn
}
