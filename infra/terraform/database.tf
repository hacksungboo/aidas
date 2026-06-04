resource "aws_dynamodb_table" "incident_table" {
  name         = "${var.project_name}-incidents"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "incident_id"   # ← 원래대로
  range_key    = "timestamp"     # ← 원래대로

  attribute {
    name = "incident_id"
    type = "S"
  }
  attribute {
    name = "timestamp"
    type = "S"
  }
  attribute {
    name = "status"
    type = "S"
  }
  attribute {
    name = "severity"
    type = "S"
  }

  global_secondary_index {
    name            = "status-timestamp-index"
    hash_key        = "status"      # ← 원래대로
    range_key       = "timestamp"   # ← 원래대로
    projection_type = "ALL"
  }

  global_secondary_index {
    name            = "severity-timestamp-index"
    hash_key        = "severity"    # ← 원래대로
    range_key       = "timestamp"   # ← 원래대로
    projection_type = "ALL"
  }

  ttl {
    attribute_name = "expires_at"
    enabled        = true
  }

  point_in_time_recovery {
    enabled = true
  }

  server_side_encryption {
    enabled = true
  }

  tags = { Name = "${var.project_name}-incidents" }
}

resource "aws_dynamodb_table" "runbook_table" {
  name         = "${var.project_name}-runbooks"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "runbook_id"  # ← 원래대로
  range_key    = "version"     # ← 원래대로

  attribute {
    name = "runbook_id"
    type = "S"
  }
  attribute {
    name = "version"
    type = "N"
  }
  attribute {
    name = "category"
    type = "S"
  }

  global_secondary_index {
    name            = "category-index"
    hash_key        = "category"  # ← 원래대로
    range_key       = "version"   # ← 원래대로
    projection_type = "ALL"
  }

  point_in_time_recovery {
    enabled = true
  }

  server_side_encryption {
    enabled = true
  }

  tags = { Name = "${var.project_name}-runbooks" }
}