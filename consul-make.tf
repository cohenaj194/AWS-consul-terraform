provider "aws" {
  # these are declared in a separate var.tf file
  access_key = "${var.aws_access_key}"
  secret_key = "${var.aws_secret_key}"
  region = "${var.region}"
}

#uploads the key pair if it doesnt already exist as terra
resource "aws_key_pair" "deployer" {
  key_name = "terra" 
  public_key = "${file(var.keypair)}"
}

resource "aws_instance" "consul" {
	ami = "ami-2d39803a"
	instance_type = "t2.micro"
	key_name = "terra"
	tags {
	  Name = "consul-server"
	}

  connection {
    user = "ubuntu"
    private_key="${file("/home/ubuntu/.ssh/id_rsa")}"
    agent = false
    timeout = "3m"
  } 

  provisioner "remote-exec" {
    inline = [<<EOF

      sudo apt-get update
      echo "gotta sleep for some reason" && sleep 5
      sudo apt-get update
      
      sudo apt-get install -y curl unzip jq

      # https://sonnguyen.ws/install-consul-and-consul-template-in-ubuntu-14-04/
      sudo mkdir -p /opt/consul /etc/consul.d/ /tmp/consul
      cd /usr/bin/
      sudo wget https://releases.hashicorp.com/consul/0.6.4/consul_0.6.4_linux_amd64.zip
      sudo unzip consul_0.6.4_linux_amd64.zip && sudo rm consul_0.6.4_linux_amd64.zip
      sudo chmod +x consul
      
      cd /opt/consul
      sudo wget sudo wget https://releases.hashicorp.com/consul/0.6.4/consul_0.6.4_web_ui.zip
      sudo unzip consul_0.6.4_web_ui.zip && sudo rm consul_0.6.4_web_ui.zip
           
      cd /usr/bin/
      sudo wget https://releases.hashicorp.com/consul-template/0.14.0/consul-template_0.14.0_linux_amd64.zip
      sudo unzip consul-template_0.14.0_linux_amd64.zip && sudo rm consul-template_0.14.0_linux_amd64.zip
      sudo chmod a+x consul-template

      #setting up rc.local to start consul on boot and chack that its running
      sudo chmod 777 /etc/rc.local 

      sudo echo '#!/bin/sh -e
      while true; do     
        if [ -z "$(ps aux | grep "consul agent" | grep -v grep)" ]; then
          # https://sonnguyen.ws/install-consul-and-consul-template-in-ubuntu-14-04/
          nohup consul agent -server -bootstrap-expect 1 \
           -data-dir /tmp/consul -node=consul-$(hostname) \
           -bind=$(hostname -i) \
           -client=0.0.0.0 \
           -config-dir /etc/consul.d \
           -ui-dir /opt/consul &

        fi
        sleep 3
      done
      exit 0' > /etc/rc.local

      sudo chmod 755 /etc/rc.local 
      sudo reboot
      
    EOF
    ]
  }

}

resource "aws_instance" "client" {
  count = 2
  ami = "ami-2d39803a"
  instance_type = "t2.micro"
  key_name = "terra"
  tags {
    Name = "consul-client"
  }

  connection {
    user = "ubuntu"
    private_key="${file("/home/ubuntu/.ssh/id_rsa")}"
    agent = false
    timeout = "3m"
  } 

  provisioner "remote-exec" {
    inline = [<<EOF

      sudo apt-get update
      echo "gotta sleep for some reason" && sleep 5
      sudo apt-get update

      #install consul
      sudo apt-get update
      sudo apt-get install -y curl unzip jq
      cd /usr/bin/
      sudo wget https://releases.hashicorp.com/consul/0.6.4/consul_0.6.4_linux_amd64.zip
      sudo unzip consul_0.6.4_linux_amd64.zip && sudo rm consul_0.6.4_linux_amd64.zip
      sudo chmod +x consul
      
      sudo mkdir -p /etc/consul.d/  /tmp/consul
      
      cd /usr/bin/
      sudo wget https://releases.hashicorp.com/consul-template/0.14.0/consul-template_0.14.0_linux_amd64.zip
      sudo unzip consul-template_0.14.0_linux_amd64.zip && sudo rm consul-template_0.14.0_linux_amd64.zip
      sudo chmod a+x consul-template

      #setting up rc.local to start consul on boot and chack that its running
      sudo chmod 777 /etc/rc.local 

      sudo echo '#!/bin/sh -e
      while true; do     
        if [ -z "$(ps aux | grep "consul agent" | grep -v grep)" ]; then
          nohup consul agent \
           -data-dir /tmp/consul \
           -bind=$(hostname -i) \
           -client=0.0.0.0 \
           -config-dir /etc/consul.d \
           -node=work-$(hostname) -retry-interval=1s \
           -retry-join ${aws_instance.consul.private_ip} &
        fi
        sleep 3
      done
      exit 0' > /etc/rc.local

      sudo chmod 755 /etc/rc.local 
      sudo reboot
      
    EOF
    ]
  }

}