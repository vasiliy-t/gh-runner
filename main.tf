

//создаем ключевую пару
resource "openstack_compute_keypair_v2" "terraform_keypair" {
  name = "terraform-keypair"
}

//создаем сеть с именем "terraform-web-net"
resource "openstack_networking_network_v2" "terraform-net" {
  name = "terraform-web-net"
  admin_state_up = "true"
}

//создаем подсеть "terraform-subnet"
resource "openstack_networking_subnet_v2" "terraform-sbnt" {
  name = "terraform-subnet"
  network_id = "${openstack_networking_network_v2.terraform-net.id}"
  cidr = "10.0.1.0/24"
  ip_version = 4
  dns_nameservers = [
    "8.8.8.8",
    "1.1.1.1"]
}

//и роутер "terraform-router"
resource "openstack_networking_router_v2" "terraform-rt" {
  name = "terraform-router"
  admin_state_up = "true"
  //id сети из которой добавляются внешние IP-адреса
  external_network_id = "298117ae-3fa4-4109-9e08-8be5602be5a2"
}

resource "openstack_networking_router_interface_v2" "terraform" {
  router_id = "${openstack_networking_router_v2.terraform-rt.id}"
  subnet_id = "${openstack_networking_subnet_v2.terraform-sbnt.id}"
}

//создаем группу безопасности, разрешающую входящие подключения по ssh/http
resource "openstack_compute_secgroup_v2" "ssh-and-http" {
  name = "allow-ssh-and-http"
  description = "Allow ssh and http traffic from everywhere"

  rule {
    from_port = 22
    to_port = 22
    ip_protocol = "tcp"
    cidr = "0.0.0.0/0"
  }

  rule {
    from_port = 80
    to_port = 80
    ip_protocol = "tcp"
    cidr = "0.0.0.0/0"
  }
}

// выделяем внешний IP-адрес из пула "ext-net"
resource "openstack_compute_floatingip_v2" "vm_floating_ip" {
  pool = "ext-net"
}


resource "openstack_compute_instance_v2" "instance" {
  name = "actions runner"
  image_name = "Ubuntu-18.04-Standard"
  //  id образа "Ubuntu-18.04-Standard"
  image_id = "f353f2aa-c847-40cd-9262-bd9c41f76003"

  flavor_name = "Basic-1-1-10"
  availability_zone = "DP1"


  key_pair = "${openstack_compute_keypair_v2.terraform_keypair.name}"
  security_groups = [
    "${openstack_compute_secgroup_v2.ssh-and-http.name}"]

  network {
    uuid = "${openstack_networking_network_v2.terraform-net.id}"
  }

  //используем внешний cloud config
  user_data = "${templatefile("cloudconfig.conf", {REPO = "", TOKEN=""})}"

  block_device {
    //id образа "Ubuntu-18.04-Standard"
    uuid = "f353f2aa-c847-40cd-9262-bd9c41f76003"
    source_type = "image"
    volume_size = 10
    boot_index = 0
    destination_type = "volume"
    delete_on_termination = true
  }
}

resource "openstack_compute_floatingip_associate_v2" "this" {
  floating_ip = "${openstack_compute_floatingip_v2.vm_floating_ip.address}"
  instance_id = "${openstack_compute_instance_v2.instance.id}"


  //исполняем inline-команды сразу после назначения белого IP
  provisioner "remote-exec" {

    //для этого подключаемся к инстансу по ssh
    connection {
      host = "${openstack_compute_floatingip_v2.vm_floating_ip.address}"
      user = "ubuntu"
      private_key = "${openstack_compute_keypair_v2.terraform_keypair.private_key}"
    }

    inline = ["cloud-init status --wait"]
  }
}

