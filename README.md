# DIY Container PaaS

A DIY container PaaS for self-serviced container deployments.

## Status: NOT FOR PRODUCTION USE

Use at your own risk!

## Motivation

Budget container PaaS solution that offers portable, self-serviced container deployments, and don't want to worry too much about:

- backups
- node failures
- scaling
- PaaS vendor lock-ins

## Features

### Basic

- [x] **Terraform** to automate provisioning of docker swarm clusters on [**Vultr**](http://vultr.com)
    - ability to add more nodes as you need them
- [x] **Docker Swarm** for container orchestration
- [x] **Traefik** for reverse proxy service (aka ingress) with automated SSL cert creation
- [x] **GlusterFS** clustered file system for:
    - container portability across the cluster
    - replicated storage

### Extended

- [ ] Better documentation
- [ ] Load balanced ingress with health-checks
- [ ] Multi-master management nodes
- [ ] Support for DigitalOcean

### Advanced

- [ ] Replace failed nodes
- [ ] Dedicated roles, e.g. databases, message queues, etc
- [ ] Centralized logging

# Quick Start

## Configure your terraform configuration `main.tf`
```tf
module "mini-pass-example" {
  source = "/tf_modules/mini-paas/vultr"
  cluster_name = "example-cluster"
  cluster_worker_count = 1
  //cluster_instance_price_per_month = "10.00"
  //cluster_ram_mb = "2048" 
  //cluster_region = "Singapore"
  dns_domain = "example.com"
  dns_acme_email = "email@example.com"
  ssh_key_source = "/deployment/resources/example_rsa"
  ssh_key_name = "example"
}
```

## Run the terraform container
```tf
# Mount your terraform configuration folder to the "/deployment" folder
docker run --rm -it -v $(pwd)/example:/deployment/ -e VULTR_API_KEY=<your-vultr-api-key> ronalddddd/mini-paas

# You are now inside the docker container's terraform environment
/deployment # terraform init
/deployment # terraform plan
/deployment # terraform apply
```

## Start using your cluster
```
# Shell into your swarm manager
ssh -i /path/to/your/sshkey root@example.com

# Check the cluster
docker node ls

# Check what's running
docker node ps
```

An example service is deployed as well. You should now be able to browse to http://whoami.example.com and get redirected to a https version.

See `tf_modules/mini-paas/resources/debugging/docker-compose.yml` for an example on deploying a web service with automatic domain and SSL setup.

## Docker Swarm Quick Reference

- `docker stack deploy --compose-file <compose_file_path> <stack_name>`
- `docker stack ps <stack_name> --no-trunc`

## References

- [squat/terraform-provider-vultr](https://github.com/squat/terraform-provider-vultr)
- http://embaby.com/blog/using-glusterfs-docker-swarm-cluster/
- https://serverfault.com/questions/531359/why-cant-i-create-this-gluster-volume
