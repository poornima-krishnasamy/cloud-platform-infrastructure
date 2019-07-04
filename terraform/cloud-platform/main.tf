# Setup
terraform {
  backend "s3" {
    bucket               = "cloud-platform-terraform-state"
    region               = "eu-west-1"
    key                  = "terraform.tfstate"
    workspace_key_prefix = "cloud-platform"
    profile              = "moj-cp"
  }
}

provider "aws" {
  region  = "eu-west-2"
  profile = "moj-cp"
}

#
# See instructions here: https://github.com/ministryofjustice/kubernetes-investigations/tree/master/auth0
#              and here: https://github.com/yieldr/terraform-provider-auth0
#
# The empty configuration assumes that you have the appropriate environment
# variables exported as explained in the upstream repo and is similar to the way
# the AWS providr credentials are handled.
#
provider "auth0" {
  version = ">= 0.1.18"
  domain  = "${local.auth0_tenant_domain}"
}

data "terraform_remote_state" "global" {
  backend = "s3"

  config {
    bucket  = "cloud-platform-terraform-state"
    region  = "eu-west-1"
    key     = "global-resources/terraform.tfstate"
    profile = "moj-cp"
  }
}

locals {
  cluster_name             = "${terraform.workspace}"
  cluster_base_domain_name = "${local.cluster_name}.cloud-platform.service.justice.gov.uk"
  auth0_tenant_domain      = "justice-cloud-platform.eu.auth0.com"
  oidc_issuer_url          = "https://${local.auth0_tenant_domain}/"

  live_domain     = "cloud-platform.service.justice.gov.uk"
  is_live_cluster = "${terraform.workspace == "live-1"}"
}

# Modules
module "cluster_dns" {
  source                   = "../modules/cluster_dns"
  cluster_base_domain_name = "${local.cluster_base_domain_name}"
  parent_zone_id           = "${data.terraform_remote_state.global.cp_zone_id}"
}

module "cluster_ssl" {
  source                   = "../modules/cluster_ssl"
  cluster_base_domain_name = "${local.cluster_base_domain_name}"
  dns_zone_id              = "${module.cluster_dns.cluster_dns_zone_id}"
}

module "cluster_vpc" {
  version              = "1.66.0"
  source               = "terraform-aws-modules/vpc/aws"
  name                 = "${local.cluster_name}"
  cidr                 = "${var.vpc_cidr}"
  azs                  = "${var.availability_zones}"
  private_subnets      = "${var.internal_subnets}"
  public_subnets       = "${var.external_subnets}"
  enable_nat_gateway   = true
  enable_vpn_gateway   = false
  enable_dns_hostnames = true

  public_subnet_tags = {
    SubnetType                                                = "Utility"
    "kubernetes.io/cluster/${local.cluster_base_domain_name}" = "shared"
    "kubernetes.io/role/elb"                                  = "1"
  }

  private_subnet_tags = {
    SubnetType                                                = "Private"
    "kubernetes.io/cluster/${local.cluster_base_domain_name}" = "shared"
    "kubernetes.io/role/internal-elb"                         = "1"
  }

  tags = {
    Terraform = "true"
    Cluster   = "${local.cluster_name}"
    Domain    = "${local.cluster_base_domain_name}"
  }
}

resource "tls_private_key" "cluster" {
  algorithm = "RSA"
  rsa_bits  = "2048"
}

resource "aws_key_pair" "cluster" {
  key_name   = "${local.cluster_base_domain_name}"
  public_key = "${tls_private_key.cluster.public_key_openssh}"
}

resource "auth0_client" "kubernetes" {
  name        = "${local.cluster_name}:kubernetes"
  description = "Cloud Platform kubernetes"
  app_type    = "regular_web"

  callbacks = [
    "${local.is_live_cluster ? format("https://login.%s/ui", local.live_domain) : "https://login.apps.${local.cluster_base_domain_name}/ui"}",
  ]

  custom_login_page_on = true
  is_first_party       = true
  oidc_conformant      = true
  sso                  = true

  jwt_configuration = {
    alg                 = "RS256"
    lifetime_in_seconds = "2592000"
  }
}

resource "auth0_client" "components" {
  name        = "${local.cluster_name}:components"
  description = "Cloud Platform components"
  app_type    = "regular_web"

  callbacks = [
    "${format("https://prometheus.%s/oauth2/callback", local.is_live_cluster ? local.live_domain : "apps.${local.cluster_base_domain_name}")}",
    "${format("https://alertmanager.%s/oauth2/callback", local.is_live_cluster ? local.live_domain : "apps.${local.cluster_base_domain_name}")}",
    "${format("https://concourse.%s/sky/issuer/callback", local.is_live_cluster ? local.live_domain : "apps.${local.cluster_base_domain_name}")}",
    "${format("https://kibana.%s/oauth2/callback", local.is_live_cluster ? local.live_domain : "apps.${local.cluster_base_domain_name}")}",
    "${format("https://kibana-audit.%s/oauth2/callback", local.is_live_cluster ? local.live_domain : "apps.${local.cluster_base_domain_name}")}",
    "${format("https://grafana.%s/login/generic_oauth", local.is_live_cluster ? local.live_domain : "apps.${local.cluster_base_domain_name}")}",
  ]

  custom_login_page_on = true
  is_first_party       = true
  oidc_conformant      = true
  sso                  = true

  jwt_configuration = {
    alg                 = "RS256"
    lifetime_in_seconds = "36000"
  }
}
