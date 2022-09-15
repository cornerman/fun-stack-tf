variable "name_prefix" {
  description = "Prefix for naming resources in the deployment."
  type        = string
  default     = null
}

variable "stage" {
  description = "The stage name, that is dev, staging, prod, etc."
  type        = string
}

variable "domain" {
  description = "Deploy under a custom domain. for this to work, you will need a hosted zone for the specified domain name in your aws account."
  type = object({
    name                = string
    deploy_to_subdomain = optional(string)
    catch_all_email     = optional(string)
  })
  default = null
}

variable "logging" {
  type = object({
    retention_in_days = optional(number)
  })
  default = {}
}

variable "dev_setup" {
  type = object({
    enabled           = optional(bool)
    local_website_url = optional(string)
  })
  default = {}
}

variable "auth" {
  description = "auth module with cognito"
  type = object({
    css_content                = optional(string)
    image_base64_content       = optional(string)
    admin_registration_only    = optional(bool)
    extra_redirect_urls        = optional(list(string))

    post_authentication_trigger = optional(object({
      source_dir    = string
      source_bucket = optional(string)
      handler       = string
      runtime       = string
      timeout       = optional(number)
      memory_size   = number
      environment   = optional(map(string))
      vpc_config = optional(object({
        subnet_ids         = list(string)
        security_group_ids = list(string)
      }))
    }))

    post_confirmation_trigger = optional(object({
      source_dir    = string
      source_bucket = optional(string)
      handler       = string
      runtime       = string
      timeout       = optional(number)
      memory_size   = number
      environment   = optional(map(string))
      vpc_config = optional(object({
        subnet_ids         = list(string)
        security_group_ids = list(string)
      }))
    }))

    pre_authentication_trigger = optional(object({
      source_dir    = string
      source_bucket = optional(string)
      handler       = string
      runtime       = string
      timeout       = optional(number)
      memory_size   = number
      environment   = optional(map(string))
      vpc_config = optional(object({
        subnet_ids         = list(string)
        security_group_ids = list(string)
      }))
    }))

    pre_sign_up_trigger = optional(object({
      source_dir    = string
      source_bucket = optional(string)
      handler       = string
      runtime       = string
      timeout       = optional(number)
      memory_size   = number
      environment   = optional(map(string))
      vpc_config = optional(object({
        subnet_ids         = list(string)
        security_group_ids = list(string)
      }))
    }))
  })
  default = null
}

variable "website" {
  description = "website module with cloudfront and s3"
  type = object({
    source_dir                  = string
    source_bucket               = optional(string)
    index_file                  = optional(string)
    error_file                  = optional(string)
    cache_files_regex           = optional(string)
    cache_files_max_age         = optional(number)
    environment                 = optional(map(string))
    rewrites                    = optional(map(string))
    content_security_policy     = optional(string)
    auth_token_in_local_storage = optional(bool)
  })
  default = null
}

variable "http" {
  description = "http module with api gateway http"
  type = object({
    allow_unauthenticated = optional(bool)

    api = optional(object({
      source_dir    = string
      source_bucket = optional(string)
      handler       = string
      runtime       = string
      timeout       = optional(number)
      memory_size   = number
      environment   = optional(map(string))
      vpc_config = optional(object({
        subnet_ids         = list(string)
        security_group_ids = list(string)
      }))
    }))

    rpc = optional(object({
      source_dir    = string
      source_bucket = optional(string)
      handler       = string
      runtime       = string
      timeout       = optional(number)
      memory_size   = number
      environment   = optional(map(string))
      vpc_config = optional(object({
        subnet_ids         = list(string)
        security_group_ids = list(string)
      }))
    }))
  })
  default = null
}

variable "ws" {
  description = "ws module with api gateway websocket"
  type = object({
    allow_unauthenticated = optional(bool)

    rpc = optional(object({
      source_dir    = string
      source_bucket = optional(string)
      handler       = string
      runtime       = string
      timeout       = optional(number)
      memory_size   = number
      environment   = optional(map(string))
      vpc_config = optional(object({
        subnet_ids         = list(string)
        security_group_ids = list(string)
      }))
    }))

    event_authorizer = optional(object({
      source_dir    = string
      source_bucket = optional(string)
      handler       = string
      runtime       = string
      timeout       = optional(number)
      memory_size   = number
      environment   = optional(map(string))
      vpc_config = optional(object({
        subnet_ids         = list(string)
        security_group_ids = list(string)
      }))
    }))
  })
  default = null
}

locals {
  module_name = replace(basename(abspath(path.module)), "_", "-")

  logging = defaults(var.logging, {
    retention_in_days = 3
  })

  dev_setup = defaults(var.dev_setup, {
    enabled = true
  })

  website = var.website == null ? null : defaults(var.website, {
    index_file                  = "index.html"
    error_file                  = "error.html"
    cache_files_regex           = ""
    cache_files_max_age         = 31536000
    auth_token_in_local_storage = true
    # content_security_policy    = "default-src 'self'; font-src https://*; img-src https://*; style-src https://*; connect-src https://* wss://*; frame-ancestors 'none'; frame-src 'none';"
  })

  ws = var.ws == null ? null : defaults(var.ws, {
    allow_unauthenticated = true
    event_authorizer = {
      timeout = 5
    }
    rpc = {
      timeout = 30
    }
  })

  http = var.http == null ? null : defaults(var.http, {
    allow_unauthenticated = true
    api = {
      timeout = 30
    }
    rpc = {
      timeout = 30
    }
  })

  auth = var.auth == null ? null : defaults(var.auth, {
    admin_registration_only = false
  })

  prefix = var.name_prefix == null ? "fun-${local.module_name}-${var.stage}" : var.name_prefix

  domain         = var.domain == null ? null : (var.domain.deploy_to_subdomain == null || var.domain.deploy_to_subdomain == "" ? var.domain.name : "${var.domain.deploy_to_subdomain}.${var.domain.name}")
  domain_website = local.domain
  domain_auth    = local.domain == null ? null : "auth.${local.domain}"
  domain_ws      = local.domain == null ? null : "ws.${local.domain}"
  domain_http    = local.domain == null ? null : "api.${local.domain}"

  url_website = length(module.website) > 0 ? (local.domain_website == null ? module.website[0].url : "https://${local.domain_website}") : null
  url_auth    = length(module.auth) > 0 ? (local.domain_auth == null ? module.auth[0].url : "https://${local.domain_auth}") : null
  url_ws      = length(module.ws) > 0 ? (local.domain_ws == null ? module.ws[0].url : "wss://${local.domain_ws}") : null
  url_http    = length(module.http) > 0 ? (local.domain_http == null ? module.http[0].url : "https://${local.domain_http}") : null

  redirect_urls = concat(
    [local.url_website],
    local.dev_setup.enabled && local.dev_setup.local_website_url != null ? [local.dev_setup.local_website_url] : []
  )
}
