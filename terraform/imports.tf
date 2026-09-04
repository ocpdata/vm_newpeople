# Recursos que ya existen en AWS (quedaron fuera del state tras un apply interrumpido).
# Estos bloques solo sincronizan el state con la infraestructura existente; se pueden
# eliminar una vez que el import haya sido aplicado exitosamente.

import {
  to = aws_vpc.main
  id = "vpc-00cbc3a44f9c75b6e"
}

import {
  to = aws_internet_gateway.main
  id = "igw-0c59e8d8fe7cd428b"
}

import {
  to = aws_subnet.private_1
  id = "subnet-0f247ae36cb35334a"
}

import {
  to = aws_subnet.private_2
  id = "subnet-0c6b9b4dfd22465ad"
}

import {
  to = aws_security_group.vm
  id = "sg-05580a0b1cb440292"
}

import {
  to = aws_security_group.rds
  id = "sg-0452dc8844fdc85d1"
}

import {
  to = aws_db_subnet_group.rds
  id = "${var.name_prefix}-db-subnets"
}

import {
  to = aws_db_instance.mysql
  id = "${var.name_prefix}-mysql"
}

# EIP publico que usa F5 como destino (52.205.148.176). El otro EIP
# (100.50.127.196, eipalloc-026485e5f68c6df65) es huerfano y no se importa.
import {
  to = aws_eip.vm
  id = "eipalloc-08db48b87b977bdeb"
}
