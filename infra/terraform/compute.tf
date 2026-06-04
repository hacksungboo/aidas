# compute.tf
# ├── ssh 키 페어 생성 (TLS 라이브러리 활용)
# ├── 최신 Amazon Linux 2023 AMI 조회
# ├── launch_template
# └── asg

# 1. SSH 키 페어 생성 (TLS 라이브러리 활용)
resource "tls_private_key" "pk" {
  algorithm = "RSA"
  rsa_bits  = 4096
}
resource "aws_key_pair" "kp" {
  key_name   = var.key_name
  public_key = tls_private_key.pk.public_key_openssh
}
resource "local_file" "ssh_key" {
  filename        = "${path.module}/${var.key_name}.pem"
  content         = tls_private_key.pk.private_key_pem
  file_permission = "0600"
}

# 3. 최신 Amazon Linux 2023 AMI 조회
data "aws_ami" "latest_al2023" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }
}

# 4. ASG 런치 템플릿(ec2 설계도) 생성
resource "aws_launch_template" "lt" {
  name_prefix            = "${var.project_name}-asg-"                 # ec2 이름 접두사
  image_id               = data.aws_ami.latest_al2023.id  # 최신 Amazon Linux 2023 AMI 사용
  instance_type          = var.instance_type              # 변수로 인스턴스 타입 지정
  vpc_security_group_ids = [aws_security_group.asg_sg.id] # ASG 보안 그룹 연결
  key_name               = aws_key_pair.kp.key_name       # SSH 키 페어 연결

  user_data = base64encode(<<-EOF
    #!/bin/bash
    dnf update -y
    dnf install -y nginx
    systemctl enable --now nginx
    echo "<h1>Hello from ASG Instance <i>$(hostname)</i> </h1>" > /usr/share/nginx/html/index.html
    # ALB 헬스체크용 엔드포인트
    mkdir -p /usr/share/nginx/html
    echo "ok" > /usr/share/nginx/html/health
    dnf install -y nginx stress
  EOF
  )

  tag_specifications {
    resource_type = "instance"
    tags          = { Name = "asg-instance" }
  }
}

# 5. ASG 생성
resource "aws_autoscaling_group" "asg" {
  name                = "${var.project_name}-asg"
  vpc_zone_identifier = [aws_subnet.private_subnet_1.id, aws_subnet.private_subnet_2.id]
  max_size            = var.max_size         # 변수로 최대 인스턴스 수 지정
  min_size            = var.min_size         # 변수로 최소 인스턴스 수 지정
  desired_capacity    = var.desired_capacity # 변수로 원하는 인스턴스 수 지정
  #위에서 만든 template정보를 등록
  launch_template {
    id      = aws_launch_template.lt.id
    version = "$Latest" # 최신 버전의 런치 템플릿 사용
  }
  # 빠른테스트를 위해 60초로 줄임설정(기본 5분)
  default_cooldown = 60
  target_group_arns = [ aws_lb_target_group.web_tg.arn ]
  health_check_type         = "ELB" # 추가사항: ALB가 /health 찌르고 200 OK 올 때만 healthy 판단(nginx 죽으면 → unhealthy → ASG가 인스턴스 교체)
  health_check_grace_period = 120 # 2분간 헬스체크 유예->nginx 기동 완료 후 체크 시작
}



# 6. ASG에 의해 생성된 EC2 인스턴스 출력
data "aws_instances" "asg_nodes" {
  # ASG가 먼저 생성되어야 된다 
  # ASG 생성이 완료될 때까지 이 조회를 기다리도록 순서를 강제합니다.
  depends_on = [aws_autoscaling_group.asg]

  # 필터링 조건: 수많은 인스턴스 중 어떤 녀석을 골라낼지 정합니다.
  instance_tags = {
    # AWS가 ASG 소속 인스턴스에 자동으로 붙여주는 "소속 태그"를 이용합니다.
    # "이 ASG 이름(${var.project_name}-${var.project_name}-asg)을 가진 그룹에 속한 애들 다 모여!" 라는 뜻입니다.
    "aws:autoscaling:groupName" = aws_autoscaling_group.asg.name
  }

  # 상태 필터: 꺼져 있거나(stopped) 생성 중인 애들은 빼고, 
  # 지금 바로 접속해서 일할 수 있는 'running' 상태인 애들만 쏙 골라냅니다.
  instance_state_names = ["running"]
}



#8. 동적 스케일링 정책
resource "aws_autoscaling_policy" "cpu_scaling_policy" {
  name                   = "${var.project_name}-cpu-target-tracking"
  autoscaling_group_name = aws_autoscaling_group.asg.name
  #대상추적방식:정해진 수치로 유지하도록 aws가 알아서 스케일링 해주는 방식
  policy_type = "TargetTrackingScaling"
  #대상추적설정
  target_tracking_configuration {
    predefined_metric_specification {
      # asg 그룹 내 모든 인스턴스의 cpu 사용 평균값
      predefined_metric_type = "ASGAverageCPUUtilization"
    }
    # 50퍼 넘으면 scale out (인스턴스 늘리고), 50퍼 밑으로 떨어지면 scale in (인스턴스 줄이는) 방식
    target_value = 50.0 # CPU 사용률이 50%를 목표로 스케일링
  }
}