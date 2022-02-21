# Get latest ubuntu from canonical account
data "aws_ami" "ubuntu_latest" {
  most_recent = true
  owners      = ["099720109477"]

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-focal-20.04-amd64-server-*"]
  }
}

# Create an instance profile to use SSM
resource "aws_iam_instance_profile" "lab_instance_profile" {
  name = "lab_instance_profile"
  role = aws_iam_role.lab_ssm_role.name
}

resource "aws_iam_role" "lab_ssm_role" {
  name = "lab_ssm_role"
  path = "/"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Principal = {
          Service = "ec2.amazonaws.com"
        },
        Effect = "Allow"
      }
    ]
  })
}
resource "aws_iam_role_policy_attachment" "lab_ssm_policy" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2RoleforSSM"
  role       = aws_iam_role.lab_ssm_role.name
}


# Assign a restrictive SG cause the instance is on the internet
resource "aws_security_group" "lab_block_all" {
  name        = "lab_block_all"
  description = "LAB block all ingress SG"

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  tags = {
    Project = "TF-lab"
  }
}

# Launch the instance
resource "aws_instance" "instance_lab" {
  ami                  = data.aws_ami.ubuntu_latest.id
  instance_type        = "t3.micro"
  iam_instance_profile = aws_iam_instance_profile.lab_instance_profile.name
  security_groups      = [aws_security_group.lab_block_all.name]

  tags = {
    Project = "TF-lab"
  }
}

# Create a KMS key for AWS Backup
resource "aws_kms_key" "lab_key" {
  description             = "LAB KMS key"
  deletion_window_in_days = 7
  tags = {
    Project = "TF-lab"
  }
}

# Create one vault
resource "aws_backup_vault" "lab_vault" {
  name        = "lab_backup_vault"
  kms_key_arn = aws_kms_key.lab_key.arn
}


# Set up one plan and a selection to backup our instance
resource "aws_backup_plan" "lab_plan" {
  name = "lab_plan"

  rule {
    rule_name         = "lab_backup_rule"
    target_vault_name = aws_backup_vault.lab_vault.name
    schedule          = "cron(0 12 * * ? *)"
  }
}

resource "aws_iam_role" "lab_backup_role" {
  name = "lab_backup_role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = ["sts:AssumeRole"]
        Effect = "allow"
        Principal = {
          Service = ["backup.amazonaws.com"]
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lab_backup_policy" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForBackup"
  role       = aws_iam_role.lab_backup_role.name
}
resource "aws_backup_selection" "lab_selection" {
  iam_role_arn = aws_iam_role.lab_backup_role.arn
  name         = "lab_backup_selection"
  plan_id      = aws_backup_plan.lab_plan.id

  resources = [
    aws_instance.instance_lab.arn
  ]
}
