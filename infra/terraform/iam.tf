# iam.tf
# ├── EC2 IAM Role (S3 접근용)
# ├── Instance Profile
# └── main.tf EC2에 연결

# ─── 1. EC2 IAM Role ──────────────────────────────────────────────
resource "aws_iam_role" "ec2_s3_role" {
  name = "${var.project_name}-ec2-s3-role"

  # EC2가 이 Role을 사용할 수 있도록 신뢰 정책 설정
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = { Name = "${var.project_name}-ec2-s3-role" }
}

# ─── 2. S3 접근 정책 ──────────────────────────────────────────────
resource "aws_iam_policy" "ec2_s3_policy" {
  name        = "${var.project_name}-ec2-s3-policy"
  description = "EC2가 S3 자산 버킷에 접근하는 권한"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # 파일 읽기
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:ListBucket"]
        Resource = [
          aws_s3_bucket.assets.arn,
          "${aws_s3_bucket.assets.arn}/*"
        ]
      },
      {
        # 로그 업로드
        Effect   = "Allow"
        Action   = ["s3:PutObject"]
        Resource = "${aws_s3_bucket.assets.arn}/logs/*"
      }
    ]
  })

  tags = { Name = "${var.project_name}-ec2-s3-policy" }
}

# ─── 3. Role에 정책 연결 ──────────────────────────────────────────
resource "aws_iam_role_policy_attachment" "ec2_s3_attach" {
  role       = aws_iam_role.ec2_s3_role.name
  policy_arn = aws_iam_policy.ec2_s3_policy.arn
}

# ─── 4. Instance Profile ──────────────────────────────────────────
resource "aws_iam_instance_profile" "ec2_profile" {
  name = "${var.project_name}-ec2-profile"
  role = aws_iam_role.ec2_s3_role.name

  tags = { Name = "${var.project_name}-ec2-profile" }
}