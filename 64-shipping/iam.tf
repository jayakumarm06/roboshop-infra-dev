#shipping
resource "aws_iam_role" "shipping" {
  name = "${var.project}-${var.environment}-shipping"

  # Terraform's "jsonencode" function converts a
  # Terraform expression result to valid JSON syntax.
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Sid    = ""
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      },
    ]
  })

  tags = merge(
    local.common_tags,
    {
      Name = "${var.project}-${var.environment}-shipping"
    }
  )
}
#shipping_password,shipping_user is using system manager policy  from iam and create role
resource "aws_iam_policy" "shipping" {
  name        = "${var.project}-${var.environment}-shipping"
  description = "IAM Policy to attach roboshop shipping instances "

  # Terraform's "jsonencode" function converts a
  # Terraform expression result to valid JSON syntax.
  policy = templatefile("${path.module}/shipping-policy.json.tftpl",
    {
      account_id  = local.account_id
      project     = var.project
      environment = var.environment
  })
  tags = merge(
    local.common_tags,
    {
      Name = "${var.project}-${var.environment}-shipping"
    }
  )

}


resource "aws_iam_role_policy_attachment" "shipping" {
  role       = aws_iam_role.shipping.name
  policy_arn = aws_iam_policy.shipping.arn
}

# 3. Create the IAM Instance Profile (This links to the role)
resource "aws_iam_instance_profile" "shipping" {
  name = "${var.project}-${var.environment}-shipping"
  role = aws_iam_role.shipping.name
}
