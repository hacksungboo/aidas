# network.tf
# ├── VPC
# ├── Subnet
# ├── Route Table
# ├── NAT Gateway
# └── ENI 


# 2. vpc 및 네트워크 생성 (인프라의 기초 공사)
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  tags = {
    Name = "${var.project_name}-vpc"
  }
}
# 인터넷 게이트 웨이
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
  tags = {
    Name = "${var.project_name}-igw"
  }
}


# 퍼블릭 서브넷1
resource "aws_subnet" "public_subnet_1" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidr1
  availability_zone       = var.avail_zone_1
  map_public_ip_on_launch = true
  tags                    = { Name = "${var.project_name}-public-subnet-1" }
}
# 퍼블릭 서브넷2
resource "aws_subnet" "public_subnet_2" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidr2
  availability_zone       = var.avail_zone_2
  map_public_ip_on_launch = true
  tags                    = { Name = "${var.project_name}-public-subnet-2" }
}

# 프라이빗 서브넷1
resource "aws_subnet" "private_subnet_1"{
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.private_subnet_cidr1
  availability_zone       = var.avail_zone_1
  map_public_ip_on_launch = false
  tags = { Name = "${var.project_name}-private-subnet-1" }
}
# 프라이빗 서브넷2
resource "aws_subnet" "private_subnet_2"{
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.private_subnet_cidr2
  availability_zone       = var.avail_zone_2
  map_public_ip_on_launch = false
  tags = { Name = "${var.project_name}-private-subnet-2" }
}
#----------------------------------------------
# 고정ip발급
resource "aws_eip" "nat_eip_a" {
  domain     = "vpc"
  depends_on = [aws_internet_gateway.igw]
  tags       = { Name = "${var.project_name}-nat-eip-a" }
}

resource "aws_eip" "nat_eip_c" {
  domain     = "vpc"
  depends_on = [aws_internet_gateway.igw]
  tags       = { Name = "${var.project_name}-nat-eip-c" }
}
# NAT 게이트웨이 생성 (각 가용영역마다 1개씩)
resource "aws_nat_gateway" "nat_a" {
  allocation_id = aws_eip.nat_eip_a.id
  subnet_id     = aws_subnet.public_subnet_1.id  # az-a 퍼블릭
  depends_on    = [aws_internet_gateway.igw]
  tags          = { Name = "${var.project_name}-nat-a" }
}

resource "aws_nat_gateway" "nat_c" {
  allocation_id = aws_eip.nat_eip_c.id
  subnet_id     = aws_subnet.public_subnet_2.id  # az-c 퍼블릭
  depends_on    = [aws_internet_gateway.igw]
  tags          = { Name = "${var.project_name}-nat-c" }
}


##---------퍼블릭 라우팅 테이블
resource "aws_route_table" "public_rt" {
  # vpc 연결
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    # 인터넷 게이트웨이 연결
    gateway_id = aws_internet_gateway.igw.id
  }
  tags = {
    Name = "${var.project_name}-public-rt"
  }
}

# 라우팅 테이블과 퍼블릭 서브넷_1 연결
resource "aws_route_table_association" "public_assoc_1" {
  subnet_id      = aws_subnet.public_subnet_1.id
  route_table_id = aws_route_table.public_rt.id
}
# 라우팅 테이블과 퍼블릭 서브넷_2 연결
resource "aws_route_table_association" "public_assoc_2" {
  subnet_id      = aws_subnet.public_subnet_2.id
  route_table_id = aws_route_table.public_rt.id
}



#-----------------프라이빗 라우팅 테이블
resource "aws_route_table" "private_rt_a" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "${var.project_name}-private-rt-a" }
}

resource "aws_route_table" "private_rt_c" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "${var.project_name}-private-rt-c" }
}

# ── NAT 경로 2개 (route 블록 대신 aws_route로 분리) ────────
resource "aws_route" "private_nat_route_a" {
  route_table_id         = aws_route_table.private_rt_a.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.nat_a.id
}

resource "aws_route" "private_nat_route_c" {
  route_table_id         = aws_route_table.private_rt_c.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.nat_c.id
}
# 라우팅 테이블과 프라이빗 서브넷_1 연결
resource "aws_route_table_association" "private_assoc_1" {
  subnet_id      = aws_subnet.private_subnet_1.id
  route_table_id = aws_route_table.private_rt_a.id
}
# 라우팅 테이블과 프라이빗 서브넷_2 연결
resource "aws_route_table_association" "private_assoc_2" {
  subnet_id      = aws_subnet.private_subnet_2.id
  route_table_id = aws_route_table.private_rt_c.id
}

# Tailscale 인증키 자동 발급
resource "tailscale_tailnet_key" "ec2_join_key" {
    reusable = true
    ephemeral = false
    preauthorized = true # 자동연결
    expiry = 2592000 # 30일
}

# Tailscale 온프레미스 연동 라우팅 (Public & Private 모두 적용)
# ----------------------------------------------------
# Public Subnet에서 172.16.8.0/24로 갈 때 EC2를 거치도록 설정

# ENI를 EC2보다 먼저 독립적으로 생성
# ─── 1. ENI 먼저 독립 생성 ───────────────────────────────────────
resource "aws_network_interface" "tailscale_eni" {
  subnet_id         = aws_subnet.private_subnet_1.id
  source_dest_check = false  # 라우터 역할 필수!
  security_groups = [
    aws_security_group.ssh_sg.id,
    aws_security_group.ec2_sg.id
    ]
  tags = {
    Name = "${var.project_name}-tailscale-eni"
  }
}
# 수정 코드 (ENI 직접 참조 - 순환 없음)
resource "aws_route" "to_onpremise_public" {
  route_table_id         = aws_route_table.public_rt.id
  destination_cidr_block = var.onpremise_cidr   # 변수로도 분리
  network_interface_id   = aws_network_interface.tailscale_eni.id  # ✅
}

resource "aws_route" "to_onpremise_private_a" {
  route_table_id         = aws_route_table.private_rt_a.id
  destination_cidr_block = var.onpremise_cidr
  network_interface_id   = aws_network_interface.tailscale_eni.id  # ✅
}

resource "aws_route" "to_onpremise_private_c" {
  route_table_id         = aws_route_table.private_rt_c.id
  destination_cidr_block = var.onpremise_cidr
  network_interface_id   = aws_network_interface.tailscale_eni.id  # ✅
}