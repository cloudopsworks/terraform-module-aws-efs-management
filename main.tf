##
# (c) 2021-2025
#     Cloud Ops Works LLC - https://cloudops.works/
#     Find us on:
#       GitHub: https://github.com/cloudopsworks
#       WebSite: https://cloudops.works
#     Distributed Under Apache v2.0 License
#

locals {
  name = var.name != "" ? var.name : format("efs-%s-%s", var.name_prefix, local.system_name_short)
}

## KMS Key with policy for EFS and Root account
data "aws_caller_identity" "current" {}
data "aws_iam_policy_document" "kms" {
  count = try(var.settings.encryption.enabled, false) && try(var.settings.encryption.kms_key_id, "") == "" ? 1 : 0
  statement {
    sid = "AllowRootAccountFullAccess"
    actions = [
      "kms:DeleteAlias",
      "kms:CreateAlias",
      "kms:CreateGrant",
      "kms:DescribeKey",
      "kms:ListGrants",
      "kms:RevokeGrant",
      "kms:GenerateDataKey",
    ]
    principals {
      type = "AWS"
      identifiers = [
        "aws:iam::${data.aws_caller_identity.current.account_id}:root",
      ]
    }
    resources = ["*"]
  }
  statement {
    sid = "AllowEFSEncyption"
    actions = [
      "kms:GenerateDataKey",
      "kms:Decrypt",
      "kms:DescribeKey",
      "kms:Encrypt",
      "kms:ReEncrypt*",
    ]
    principals {
      type        = "Service"
      identifiers = ["elasticfilesystem.amazonaws.com"]
    }
    resources = ["*"]
  }
}

resource "aws_kms_key" "this" {
  count                   = try(var.settings.encryption.enabled, false) && try(var.settings.encryption.kms_key_id, "") == "" ? 1 : 0
  description             = format("KMS Key for %s EFS", local.name)
  deletion_window_in_days = try(var.settings.encryption.deletion_window_in_days, 30)
  enable_key_rotation     = true
  rotation_period_in_days = try(var.settings.encryption.rotation_period_in_days, 90)
  policy                  = data.aws_iam_policy_document.kms[0].json
  tags                    = local.all_tags
}

resource "aws_kms_alias" "this" {
  count         = try(var.settings.encryption.enabled, false) && try(var.settings.encryption.kms_key_id, "") == "" ? 1 : 0
  target_key_id = aws_kms_key.this[0].id
  name          = format("alias/efs-%s", local.name)
}

resource "aws_efs_file_system" "this" {
  creation_token = local.name
  encrypted      = try(var.settings.encryption.enabled, false)
  kms_key_id     = try(var.settings.encryption.kms_key_id, null)
  dynamic "lifecycle_policy" {
    for_each = length(try(var.settings.lifecycle_policy, {})) > 0 ? [1] : []
    content {
      transition_to_ia                    = try(var.settings.lifecycle_policy.transition_to_ia, null)
      transition_to_archive               = try(var.settings.lifecycle_policy.transition_to_archive, null)
      transition_to_primary_storage_class = try(var.settings.lifecycle_policy.transition_to_primary_storage_class, null)
    }
  }
  dynamic "protection" {
    for_each = try(var.settings.replication_overwrite, null) != null ? [1] : []
    content {
      replication_overwrite = var.settings.replication_overwrite
    }
  }
  provisioned_throughput_in_mibps = try(var.settings.provisioned_throughput_in_mibps, null)
  throughput_mode                 = try(var.settings.throughput_mode, null)
  performance_mode                = try(var.settings.performance_mode, null)
  tags                            = local.all_tags
}

resource "aws_efs_access_point" "this" {
  for_each       = try(var.settings.access_points, {})
  file_system_id = aws_efs_file_system.this.id
  dynamic "posix_user" {
    for_each = length(try(each.value.posix_user, {})) > 0 ? [1] : []
    content {
      uid            = try(each.value.posix_user.uid, null)
      gid            = try(each.value.posix_user.gid, null)
      secondary_gids = try(each.value.posix_user.secondary_gids, null)
    }
  }
  dynamic "root_directory" {
    for_each = length(try(each.value.root_directory, {})) > 0 ? [1] : []
    content {
      path = try(each.value.root_directory.path, null)
      dynamic "creation_info" {
        for_each = length(try(each.value.root_directory.creation_info, {})) > 0 ? [1] : []
        content {
          owner_uid   = try(each.value.root_directory.creation_info.owner_uid, null)
          owner_gid   = try(each.value.root_directory.creation_info.owner_gid, null)
          permissions = try(each.value.root_directory.creation_info.permissions, null)
        }
      }
    }
  }
  tags = local.all_tags
}

resource "aws_efs_mount_target" "this" {
  for_each = {
    for index, subnet in try(var.settings.mount_targets, []) : index => subnet
  }
  file_system_id  = aws_efs_file_system.this.id
  subnet_id       = each.value.subnet_id
  security_groups = try(each.value.security_groups, null)
  ip_address      = try(each.value.ip_address, null)
}