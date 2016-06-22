variable "digitalocean_ssh_id_rsa_fingerprint" {}
variable "digitalocean_ssh_id_rsa" {}
variable "digitalocean_ssh_id_rsa_pub" {}
variable "do_token" {}

provider "digitalocean" {
  token = "${var.do_token}"
}

resource "digitalocean_droplet" "home" {
    image = "ubuntu-14-04-x64"
    name = "home"
    region = "lon1"
    size = "512mb"
    ssh_keys = [ 2079352, 2079601, 2079581, 2079662 ]

    provisioner "remote-exec" {
        connection {
            type = "ssh"
            user = "root"
            private_key = "${var.digitalocean_ssh_id_rsa}"
            agent = false
        }

        inline = [
            # "touch /root/hello_world"
            "apt-get -y update",

            # Swap
            "install -o root -g root -m 0600 /dev/null /swapfile",
            "dd if=/dev/zero of=/swapfile bs=1k count=2048k",
            "mkswap /swapfile",
            "swapon /swapfile",
            "echo '/swapfile       swap    swap    auto      0       0' | tee -a /etc/fstab",
            "sysctl -w vm.swappiness=10",
            "echo vm.swappiness = 10 | tee -a /etc/sysctl.conf",

            "echo GatewayPorts clientspecified | tee -a /etc/ssh/sshd_config",
            "echo Match User loanbot | tee -a /etc/ssh/sshd_config",
            "echo \"  PasswordAuthentication no\" | tee -a /etc/ssh/sshd_config",
            # Git
            "apt-get -y install git",

            # Account for loanbot to run on
            "adduser --disabled-password --gecos \"\" loanbot",

            # Authorized Keys
            "mkdir -p /home/loanbot/.ssh",
            "ssh-keygen -t rsa -N \"\" -f /home/loanbot/.ssh/id_rsa",
            "echo ${file(concat(path.module, \"/ssh/id_rsa.pub\"))} >> /home/loanbot/.ssh/authorized_keys",
            "chmod 700 /home/loanbot/.ssh",
            "chmod 600 /home/loanbot/.ssh/authorized_keys",
            "chown -R loanbot:loanbot /home/loanbot/.ssh",
            "service ssh reload",

            # Necessary services for the loanbot
            "apt-get -y install build-essential libssl-dev",

            # Loanbot
            "su loanbot",
            "cd /home/loanbot"
            "curl https://raw.githubusercontent.com/creationix/nvm/v0.25.0/install.sh | bash",
            "source ~/.profile",
            "nvm install v6.2",
            "git clone git@github.com:ThomasRooney/loanbot.git"
        ]
    }
}
