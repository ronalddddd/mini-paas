variable "cluster_name" {}
variable "cluster_worker_count" {}
variable "dns_domain" {}
variable "dns_acme_email" {}
variable "ssh_key_source" {}
variable "ssh_key_name" {}

variable "cluster_region" {
  default = "Singapore"
}

variable "cluster_instance_price_per_month" {
  default = "10.00"
}

variable "cluster_instance_ram_mb" {
  default = "2048"
}

variable "swarm_volumes_path" {
  default = "/swarm/volumes"
}


data "vultr_region" "default" {
  filter {
    name = "name"
    values = ["${var.cluster_region}"]
  }
}

data "vultr_plan" "default" {
  filter {
    name = "price_per_month"
    values = ["${var.cluster_instance_price_per_month}"]
  }

  filter {
    name = "ram"
    values = ["${var.cluster_instance_ram_mb}"]
  }
}

data "vultr_ssh_key" "default" {
  filter {
    name = "name"
    values = ["${var.ssh_key_name}"]
  }
}

data "vultr_os" "ubuntu" {
  filter {
    name = "family"
    values = ["ubuntu"]
  }

  filter {
    name = "name"
    values = ["Ubuntu 16.04 x64"]
  }
}

data "template_file" "traefik_toml" {
  template = "${file("${path.module}/../resources/traefik/traefik.toml")}"

  vars {
    dns_domain = "${var.dns_domain}"
    dns_acme_email = "${var.dns_acme_email}"
  }
}

data "template_file" "traefik_compose" {
  template = "${file("${path.module}/../resources/traefik/docker-compose.yml")}"

  vars {
    swarm_volumes_path = "${var.swarm_volumes_path}"
  }
}

data "template_file" "whoami_compose" {
  template = "${file("${path.module}/../resources/debugging/docker-compose.yml")}"

  vars {
    dns_domain = "${var.dns_domain}"
  }
}

locals {
  ## Provisioning commands
  docker_ce_install = [
        "curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -",
        <<EOF
sudo add-apt-repository \
   "deb [arch=amd64] https://download.docker.com/linux/ubuntu \
   $(lsb_release -cs) \
   stable"
EOF
,
    "apt update -y",
    "apt install -y docker-ce",
  ]
}


// Create a Vultr virtual machine.
resource "vultr_instance" "master" {
  name = "${var.cluster_name}-master"
  hostname = "${var.cluster_name}-master.${var.dns_domain}"
  region_id = "${data.vultr_region.default.id}"
  plan_id = "${data.vultr_plan.default.id}"
  os_id = "${data.vultr_os.ubuntu.id}"
  tag = "${var.cluster_name}"
  private_networking = true
  ssh_key_ids = ["${data.vultr_ssh_key.default.id}"]
  //  firewall_group_id =
  //  user_data =
  //  startup_script_id =

  # Private networking setup
  provisioner "remote-exec" {
    inline = [
      <<HCL_EOF
cat <<EOF >> /etc/network/interfaces
auto ens7
  iface ens7 inet static
  address ${vultr_instance.master.ipv4_private_address}
  netmask 255.255.0.0
  mtu 1450
EOF
HCL_EOF
,
        "ifup ens7"
      ]
  }

  # Setup GlusterFS, create the volume and mount it
  provisioner "remote-exec" {
    inline = [
      "sleep 60",
      "apt update -y",
      "apt install -y glusterfs-server",
      "mkdir -p /gluster/data ${var.swarm_volumes_path}",
      "gluster volume create swarm-vols ${vultr_instance.master.ipv4_private_address}:/gluster/data force",
      "gluster volume set swarm-vols auth.allow 127.0.0.1",
      "gluster volume start swarm-vols",
      "mount.glusterfs localhost:/swarm-vols ${var.swarm_volumes_path}",
      ]
  }

  # Install docker-ce
  provisioner "remote-exec" {
    inline = "${local.docker_ce_install}"
  }

  # Init the swarm
  provisioner "remote-exec" {
    inline = [
      "docker swarm init --advertise-addr ${self.ipv4_private_address}",
    ]
  }

  # Prepare the traefik and debugging stacks folder
  provisioner "remote-exec" {
    inline = [
      "mkdir ${var.swarm_volumes_path}/traefik",
      "touch ${var.swarm_volumes_path}/traefik/acme.json",
      "mkdir ${var.swarm_volumes_path}/debugging",
    ]
  }

  # Copy the templated traefik configuration
  provisioner "file" {
    content = "${data.template_file.traefik_toml.rendered}"
    destination = "${var.swarm_volumes_path}/traefik/traefik.toml"
  }

  # Copy the templated traefik compose file
  provisioner "file" {
    content = "${data.template_file.traefik_compose.rendered}"
    destination = "${var.swarm_volumes_path}/traefik/docker-compose.yml"
  }

  # Deploy the ingress stack (Traefik)
  provisioner "remote-exec" {
    inline = [
      "docker stack deploy --compose-file ${var.swarm_volumes_path}/traefik/docker-compose.yml ingress"
    ]
  }

  # Copy the templated debugging stack compose file
  provisioner "file" {
    content = "${data.template_file.whoami_compose.rendered}"
    destination = "${var.swarm_volumes_path}/debugging/docker-compose.yml"
  }

  # Deploy the debugging stack (whoami)
  provisioner "remote-exec" {
    inline = [
      "docker stack deploy --compose-file ${var.swarm_volumes_path}/debugging/docker-compose.yml debugging"
    ]
  }

}

resource "vultr_instance" "worker" {
  count = "${var.cluster_worker_count}"
  name = "${var.cluster_name}-worker${count.index}"
  hostname = "${var.cluster_name}-worker${count.index}.${var.dns_domain}"
  region_id = "${data.vultr_region.default.id}"
  plan_id = "${data.vultr_plan.default.id}"
  os_id = "${data.vultr_os.ubuntu.id}"
  tag = "${var.cluster_name}"
  private_networking = true
  ssh_key_ids = ["${data.vultr_ssh_key.default.id}"]
  //  firewall_group_id =
  //  user_data =
  //  startup_script_id =

  # Private networking setup
  provisioner "remote-exec" {
    inline = [
      <<HCL_EOF
cat <<EOF >> /etc/network/interfaces
auto ens7
  iface ens7 inet static
  address ${self.ipv4_private_address}
  netmask 255.255.0.0
  mtu 1450
EOF
HCL_EOF
,
        "ifup ens7"
      ]
  }

  # Private key to access master
  provisioner "file" {
    source = "${var.ssh_key_source}"
    destination = "/root/secret_key"
  }

  # Prep
  provisioner "remote-exec" {
    inline = [
      "sleep 60",
      "chmod 0600 /root/secret_key",
      "apt update -y",
    ]
  }

  # Setup GlusterFS and join the volume
  provisioner "remote-exec" {
    inline = [
      "apt install -y glusterfs-server",
      "mkdir -p /gluster/data ${var.swarm_volumes_path}",
      "ssh -o StrictHostKeyChecking=no -i /root/secret_key root@${vultr_instance.master.ipv4_private_address} 'gluster peer probe ${self.ipv4_private_address}'",
      "ssh -o StrictHostKeyChecking=no -i /root/secret_key root@${vultr_instance.master.ipv4_private_address} 'gluster volume add-brick swarm-vols replica ${count.index + 2} ${self.ipv4_private_address}:/gluster/data force'",
      "mount.glusterfs localhost:/swarm-vols ${var.swarm_volumes_path}",
    ]
  }

  # Install docker-ce
  provisioner "remote-exec" {
    inline = "${local.docker_ce_install}"
  }

  # Get token and join swarm
  provisioner "remote-exec" {
    inline = [
      "ssh -o StrictHostKeyChecking=no -i /root/secret_key root@${vultr_instance.master.ipv4_private_address} 'docker swarm join-token worker -q > /root/swarm_token'",
      "scp -o StrictHostKeyChecking=no -i /root/secret_key root@${vultr_instance.master.ipv4_private_address}:/root/swarm_token /root/swarm_token",
      "docker swarm join --token $(cat /root/swarm_token) ${vultr_instance.master.ipv4_private_address}",
    ]
  }

  # Cleanup
  provisioner "remote-exec" {
    inline = [
      "rm /root/secret_key",
    ]
  }
}

// Create a DNS domain.
resource "vultr_dns_domain" "default" {
  domain = "${var.dns_domain}"
  ip     = "${vultr_instance.master.ipv4_address}"
}

// Create a wild card DNS record.
resource "vultr_dns_record" "default" {
  domain = "${vultr_dns_domain.default.id}"
  name   = "*"
  type   = "CNAME"
  data   = "${var.dns_domain}"
  ttl    = 300
}