data "aws_caller_identity" "current" {}

data "aws_eks_cluster" "clusters" {
  count = var.enable_kubernetes_integration ? length(var.eks_cluster_arns) : 0
  name  = element(split("/", var.eks_cluster_arns[count.index]), length(split("/", var.eks_cluster_arns[count.index])) - 1)
}

locals {
  all_clusters_info = var.enable_kubernetes_integration ? [
    for i, cluster in data.aws_eks_cluster.clusters : {
      oidc_id = split("/", cluster.identity[0].oidc[0].issuer)[4]
      region  = split(":", var.eks_cluster_arns[i])[3] # Extract region from ARN
    }
  ] : []

  all_oidc_ids = [for cluster in local.all_clusters_info : cluster.oidc_id]
  eks_oidc_provider_arns = var.enable_kubernetes_integration ? [
    for cluster in local.all_clusters_info :
    "arn:aws:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/oidc.eks.${cluster.region}.amazonaws.com/id/${cluster.oidc_id}"
  ] : []
}

data "aws_iam_policy_document" "assume_role_policy" {
  statement {
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = [local.nullify_role_arn]
    }
    actions = ["sts:AssumeRole"]
    condition {
      test     = "StringEquals"
      variable = "sts:ExternalId"
      values   = [var.external_id]
    }
  }

  dynamic "statement" {
    for_each = var.enable_kubernetes_integration ? local.all_clusters_info : []
    content {
      effect = "Allow"
      principals {
        type        = "Federated"
        identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/oidc.eks.${statement.value.region}.amazonaws.com/id/${statement.value.oidc_id}"]
      }
      actions = ["sts:AssumeRoleWithWebIdentity"]
      condition {
        test     = "StringEquals"
        variable = "oidc.eks.${statement.value.region}.amazonaws.com/id/${statement.value.oidc_id}:sub"
        values   = [local.oidc_subject]
      }
    }
  }
}

data "aws_iam_policy_document" "readonly_policy_part1" {
  statement {
    effect = "Allow"
    actions = [
      "access-analyzer:List*",
      "acm:Describe*",
      "acm:List*",
      "apigateway:GET",
      "apprunner:DescribeService",
      "apprunner:List*",
      "appsync:ListGraphqlApis",
      "athena:GetWorkGroup",
      "athena:List*",
      "backup:GetBackupPlan",
      "backup:GetBackupVaultAccessPolicy",
      "backup:List*",
      "cloudfront:List*",
      "cloudtrail:Describe*",
      "cloudtrail:GetEventDataStore",
      "cloudtrail:GetTrailStatus",
      "cloudtrail:List*",
      "cloudwatch:Describe*",
      "codebuild:BatchGetProjects",
      "codebuild:List*",
      "cognito-identity:Describe*",
      "cognito-identity:List*",
      "cognito-idp:DescribeUserPool",
      "cognito-idp:ListUserPools",
      "config:Describe*",
      "dynamodb:Describe*",
      "dynamodb:GetResourcePolicy",
      "dynamodb:List*",
      "ec2:Describe*",
      "ec2:GetEbsEncryptionByDefault",
      "ec2:GetManagedPrefixListEntries",
      "ec2:GetSnapshotBlockPublicAccessState",
      "ec2:SearchTransitGateway*",
      "ecr:Describe*",
      "ecr:GetLifecyclePolicy",
      "ecr:GetRepositoryPolicy",
      "ecs:Describe*",
      "ecs:List*",
      "eks:Describe*",
      "eks:List*",
      "elasticache:Describe*",
      "elasticfilesystem:Describe*",
      "elasticloadbalancing:Describe*",
      "elasticmapreduce:Describe*",
      "elasticmapreduce:GetBlockPublicAccessConfiguration",
      "elasticmapreduce:List*",
      "es:Describe*",
      "es:List*",
      "events:List*",
      "globalaccelerator:List*",
      "glue:GetCrawlers",
      "glue:GetDataCatalogEncryptionSettings",
      "glue:GetDevEndpoints",
      "glue:GetJobs"
    ]
    resources = ["*"]
  }
}

data "aws_iam_policy_document" "readonly_policy_part2" {
  statement {
    effect = "Allow"
    actions = [
      "glue:GetSecurityConfigurations",
      "guardduty:GetDetector",
      "guardduty:List*",
      "iam:GenerateCredentialReport",
      "iam:Get*",
      "iam:List*",
      "kafka:List*",
      "kinesis:Describe*",
      "kinesis:List*",
      "kms:Describe*",
      "kms:GetKeyPolicy",
      "kms:GetKeyRotationStatus",
      "kms:List*",
      "lambda:GetFunction",
      "lambda:GetFunctionUrlConfig",
      "lambda:GetPolicy",
      "lambda:List*",
      "logs:Describe*",
      "memorydb:Describe*",
      "memorydb:List*",
      "mq:Describe*",
      "mq:List*",
      "neptune:Describe*",
      "neptune:List*",
      "network-firewall:Describe*",
      "network-firewall:List*",
      "organizations:Describe*",
      "organizations:List*",
      "rds:Describe*",
      "redshift:Describe*",
      "route53:List*",
      "s3:GetAccountPublicAccessBlock",
      "s3:GetBucket*",
      "s3:GetEncryptionConfiguration",
      "s3:GetLifecycleConfiguration",
      "s3:GetReplicationConfiguration",
      "s3:ListAllMyBuckets",
      "sagemaker:Describe*",
      "sagemaker:List*",
      "secretsmanager:GetResourcePolicy",
      "secretsmanager:List*",
      "sns:GetTopicAttributes",
      "sns:List*",
      "sqs:GetQueueAttributes",
      "sqs:List*",
      "ssm:Describe*",
      "ssm:GetDocument",
      "ssm:ListDocuments",
      "states:DescribeStateMachine",
      "states:List*",
      "sts:GetCallerIdentity",
      "wafv2:GetWebACL",
      "wafv2:List*"
    ]
    resources = ["*"]
  }
}

data "aws_iam_policy_document" "s3_access_policy" {
  count = local.enable_s3_access ? 1 : 0

  statement {
    effect = "Allow"
    actions = [
      "s3:PutObject",
      "s3:ListBucket",
      "s3:PutObjectAcl"
    ]
    resources = [
      local.s3_bucket_arn,
      "${local.s3_bucket_arn}/*"
    ]
  }
}

data "aws_iam_policy_document" "kms_access_policy" {
  count = local.enable_kms_access ? 1 : 0

  statement {
    effect = "Allow"
    actions = [
      "kms:DescribeKey",
      "kms:GenerateDataKey",
      "kms:GenerateDataKeyWithoutPlaintext",
      "kms:ReEncryptFrom",
      "kms:ReEncryptTo"
    ]
    resources = [var.kms_key_arn]
  }
}

data "aws_iam_policy_document" "deny_actions_policy" {
  statement {
    effect = "Deny"
    actions = [
      "s3:GetObject",
      "s3:GetObject*",
      "s3:DeleteObject*",
      "s3:RestoreObject",
      "ecr:GetDownloadUrlForLayer",
      "ecr:BatchGetImage",
      "ecr:GetAuthorizationToken",
      "ecr:PutImage",
      "ecr:InitiateLayerUpload",
      "ecr:UploadLayerPart",
      "ecr:CompleteLayerUpload",
      "secretsmanager:GetSecretValue",
      "secretsmanager:DescribeSecret",
      "ssm:GetParameter*",
      "ssm:PutParameter*",
      "ssm:DeleteParameter*",
      "kms:Decrypt",
      "lambda:InvokeFunction",
      "lambda:InvokeAsync",
      "sts:AssumeRole",
      "iam:PassRole",
      "iam:CreateRole",
      "iam:DeleteRole",
      "iam:AttachRolePolicy",
      "iam:DetachRolePolicy",
      "iam:PutRolePolicy",
      "iam:DeleteRolePolicy",
      "iam:CreateUser",
      "iam:DeleteUser",
      "iam:CreateAccessKey",
      "iam:DeleteAccessKey",
      "iam:UpdateAccessKey",
      "ec2:RunInstances",
      "ec2:TerminateInstances",
      "ec2:StopInstances",
      "ec2:StartInstances",
      "ec2:RebootInstances",
      "ec2:CreateSnapshot",
      "ec2:DeleteSnapshot",
      "ec2:CreateImage",
      "ec2:DeregisterImage",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "logs:DeleteLogGroup",
      "logs:DeleteLogStream",
      "athena:GetQueryResults",
      "cloudtrail:GetQueryResults",
      "cognito-idp:AdminListUserAuthEvents",
      "cognito-idp:ListUsers",
      "dynamodb:BatchGetItem",
      "dynamodb:GetItem",
      "dynamodb:Query",
      "dynamodb:Scan",
      "es:ESHttp*",
      "glue:GetConnection",
      "glue:GetConnections",
      "glue:GetPartition*",
      "glue:GetTable*",
      "kinesis:GetRecords",
      "kinesis:GetShardIterator",
      "lakeformation:GetDataAccess",
      "lakeformation:GetTemporaryGlue*",
      "lightsail:GetInstanceAccessDetails",
      "logs:FilterLogEvents",
      "logs:GetLogEvents",
      "logs:StartQuery",
      "rds-data:*",
      "rekognition:Detect*",
      "sdb:Select*",
      "sqs:ReceiveMessage",
      "wafv2:GetRateBasedStatementManagedKeys",
      "wafv2:GetSampledRequests",
      "workmail:Search*",
      "clouddirectory:BatchRead",
      "cloudfront-keyvaluestore:GetKey",
      "cloudfront-keyvaluestore:ListKeys",
      "cognito-idp:ListUsersInGroup",
      "cognito-sync:ListRecords",
      "cognito-sync:QueryRecords",
      "dynamodb:PartiQLSelect",
      "kinesis:SubscribeToShard",
      "lightsail:GetRelationalDatabaseMasterUserPassword",
      "logs:StartLiveTail",
      "medialive:GetInputDeviceThumbnail",
      "pi:DescribeDimensionKeys",
      "rum:GetAppMonitorData",
      "aps:QueryMetrics",
      "s3-outposts:GetObject",
      "s3-outposts:GetObjectVersion",
      "ssm:ListCommandInvocations",
      "states:DescribeExecution",
      "states:GetExecutionHistory",
      "storagegateway:DescribeChapCredentials",
      "support:DescribeCases",
      "support:DescribeCommunications",
      "support:SearchForCases",
      "transfer:TestIdentityProvider",
      "verifiedpermissions:IsAuthorized",
      "verifiedpermissions:IsAuthorizedWithToken",
      "appstream:DescribeSessions",
      "appstream:DescribeUsers",
      "appsync:ListApiKeys",
      "cognito-identity:LookupDeveloperIdentity",
      "cognito-idp:AdminListDevices",
      "cognito-idp:DescribeUserPoolClient",
      "identitystore:DescribeUser",
      "kinesisanalytics:DiscoverInputSchema",
      "lakeformation:GetWorkUnitResults",
      "lakeformation:GetWorkUnits",
      "lightsail:GetContainerLog",
      "notifications:GetManagedNotificationEvent",
      "notifications:GetNotificationEvent",
      "rekognition:ListFaces",
      "rekognition:ListUsers",
      "sso:ListAccountAssignments",
      "sso:ListAccountAssignmentsForPrincipal",
      "support:DescribeAttachment",
      "workmail:DescribeUser",
      "workmail:ListAliases",
      "workmail:ListUsers",
      "workspaces:DescribeWorkspaces",
      "workmailmessageflow:GetRawMessageContent"
    ]
    resources = ["*"]
  }
}
