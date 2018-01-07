module "mini-pass-example" {
  source = "/tf_modules/mini-paas/vultr"
  cluster_name = "example-cluster"
  cluster_worker_count = 1
  dns_domain = "example.com"
  dns_acme_email = "email@example.com"
  ssh_key_source = "/deployment/resources/example_rsa"
  ssh_key_name = "example"
}