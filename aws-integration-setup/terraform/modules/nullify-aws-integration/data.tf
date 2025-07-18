data "aws_caller_identity" "current" {}

data "aws_eks_cluster" "clusters" {
  count = var.enable_kubernetes_integration ? length(var.eks_cluster_arns) : 0
  name  = element(split("/", var.eks_cluster_arns[count.index]), length(split("/", var.eks_cluster_arns[count.index])) - 1)
}

locals {
  all_clusters_info = var.enable_kubernetes_integration ? [
    for i, cluster in data.aws_eks_cluster.clusters : {
      oidc_id = split("/", cluster.identity[0].oidc[0].issuer)[4]
      region  = split(":", var.eks_cluster_arns[i])[3]  # Extract region from ARN
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
      "a4b:List*",
      "access-analyzer:GetAccessPreview",
      "access-analyzer:GetAnalyzedResource",
      "access-analyzer:GetAnalyzer",
      "access-analyzer:GetArchiveRule",
      "access-analyzer:GetFinding",
      "access-analyzer:GetFindingsStatistics",
      "access-analyzer:GetGeneratedPolicy",
      "access-analyzer:List*",
      "access-analyzer:ValidatePolicy",
      "account:GetAccountInformation",
      "account:GetAlternateContact",
      "account:GetContactInformation",
      "account:GetPrimaryEmail",
      "account:GetRegionOptStatus",
      "account:ListRegions",
      "acm-pca:Describe*",
      "acm-pca:List*",
      "acm:Describe*",
      "acm:List*",
      "aiops:List*",
      "airflow:List*",
      "amplify:GetBranch",
      "amplify:GetDomainAssociation",
      "amplify:GetWebhook",
      "amplify:List*",
      "aoss:BatchGetLifecyclePolicy",
      "aoss:BatchGetVpcEndpoint",
      "aoss:GetAccessPolicy",
      "aoss:GetAccountSettings",
      "aoss:GetPoliciesStats",
      "aoss:GetSecurityConfig",
      "aoss:GetSecurityPolicy",
      "aoss:List*",
      "apigateway:GET",
      "appconfig:List*",
      "appfabric:List*",
      "appflow:List*",
      "application-autoscaling:Describe*",
      "application-autoscaling:ListTagsForResource",
      "application-signals:List*",
      "application-signals:ListTagsForResource",
      "applicationinsights:List*",
      "appmesh:Describe*",
      "appmesh:List*",
      "apprunner:DescribeAutoScalingConfiguration",
      "apprunner:DescribeCustomDomains",
      "apprunner:DescribeObservabilityConfiguration",
      "apprunner:DescribeService",
      "apprunner:DescribeVpcConnector",
      "apprunner:DescribeVpcIngressConnection",
      "apprunner:DescribeWebAclForService",
      "apprunner:List*",
      "appstream:Describe*",
      "appstream:List*",
      "appsync:List*",
      "apptest:ListTagsForResource",
      "apptest:List*",
      "aps:DescribeAlertManagerDefinition",
      "aps:DescribeLoggingConfiguration",
      "aps:DescribeRuleGroupsNamespace",
      "aps:DescribeScraper",
      "aps:DescribeWorkspace",
      "aps:List*",
      "aps:ListWorkspaces",
      "aps:QueryMetrics",
      "arc-zonal-shift:GetAutoshiftObserverNotificationStatus",
      "arc-zonal-shift:ListAutoshifts",
      "arc-zonal-shift:ListManagedResources",
      "arc-zonal-shift:ListZonalShifts",
      "artifact:ListAgreements",
      "artifact:ListCustomerAgreements",
      "artifact:ListReports",
      "athena:List*",
      "auditmanager:List*",
      "auditmanager:ListTagsForResource",
      "auditmanager:ValidateAssessmentReportIntegrity",
      "autoscaling-plans:Describe*",
      "autoscaling:Describe*",
      "backup-gateway:List*",
      "backup:Describe*",
      "backup:List*",
      "batch:Describe*",
      "batch:List*",
      "bedrock:List*",
      "billingconductor:List*",
      "cloud9:Describe*",
      "cloud9:List*",
      "clouddirectory:BatchRead",
      "clouddirectory:List*",
      "clouddirectory:LookupPolicy",
      "cloudformation:Describe*",
      "cloudformation:Detect*",
      "cloudformation:Estimate*",
      "cloudformation:List*",
      "cloudformation:ValidateTemplate",
      "cloudfront-keyvaluestore:Describe*",
      "cloudfront-keyvaluestore:List*",
      "cloudfront:Describe*",
      "cloudfront:List*",
      "cloudhsm:Describe*",
      "cloudhsm:List*",
      "cloudsearch:Describe*",
      "cloudsearch:List*",
      "cloudtrail:Describe*",
      "cloudtrail:Get*",
      "cloudtrail:List*",
      "cloudtrail:LookupEvents",
      "cloudwatch:Describe*",
      "cloudwatch:GenerateQuery",
      "codeartifact:List*",
      "codebuild:Describe*",
      "cognito-identity:Describe*",
      "cognito-identity:GetIdentityPoolAnalytics",
      "cognito-identity:GetIdentityPoolDailyAnalytics",
      "cognito-identity:GetIdentityPoolRoles",
      "cognito-identity:GetIdentityProviderDailyAnalytics",
      "cognito-identity:List*",
      "cognito-identity:Lookup*",
      "cognito-idp:AdminList*",
      "cognito-idp:Describe*",
      "cognito-idp:List*",
      "cognito-sync:Describe*",
      "cognito-sync:List*",
      "cognito-sync:QueryRecords",
      "config:SelectResourceConfig",
      "devops-guru:List*",
      "discovery:Describe*",
      "discovery:List*",
      "ecr-public:BatchCheckLayerAvailability",
      "ecr-public:DescribeImages",
      "ecr-public:DescribeImageTags",
      "ecr-public:DescribeRegistries",
      "ecr-public:DescribeRepositories",
      "ecr-public:GetRepositoryCatalogData",
      "ecr-public:GetRepositoryPolicy",
      "ecr-public:ListTagsForResource",
      "ecr:BatchCheck*",
      "ecr:Describe*",
      "ecr:List*",
      "ecs:Describe*",
      "ecs:List*",
      "eks:Describe*",
      "eks:List*",
      "elastic-inference:Describe*",
      "elastic-inference:List*",
      "elasticache:Describe*",
      "elasticache:List*",
      "elasticbeanstalk:Check*",
      "elasticbeanstalk:Describe*",
      "elasticbeanstalk:List*",
      "elasticfilesystem:Describe*",
      "elasticfilesystem:ListTagsForResource",
      "elasticloadbalancing:Describe*",
      "elasticmapreduce:Describe*",
      "elasticmapreduce:GetBlockPublicAccessConfiguration",
      "elasticmapreduce:List*",
      "elasticmapreduce:View*",
      "elastictranscoder:List*",
      "elastictranscoder:Read*",
      "emr-containers:Describe*",
      "emr-containers:List*",
      "glue:Describe*",
      "glue:List*",
      "iam:Get*",
      "iam:List*",
      "iam:Simulate*",
      "iam:SimulateCustomPolicy",
      "iam:SimulatePrincipalPolicy",
      "identity-sync:ListSyncFilters",
      "identitystore:Describe*",
      "iotfleetwise:List*",
      "iotroborunner:List*",
      "iotsitewise:Describe*",
      "iotsitewise:List*",
      "iotwireless:List*",
      "ivs:List*",
      "ivschat:List*",
      "kafka:Describe*",
      "kafka:List*",
      "kafkaconnect:List*",
      "kendra:BatchGetDocumentStatus",
      "kendra:DescribeDataSource",
      "kendra:DescribeExperience",
      "kendra:DescribeFaq",
      "kendra:DescribeIndex",
      "kendra:DescribePrincipalMapping",
      "kendra:DescribeQuerySuggestionsBlockList",
      "kendra:DescribeQuerySuggestionsConfig",
      "kendra:DescribeThesaurus",
      "kendra:List*",
      "kinesis:Describe*",
      "kinesis:List*",
      "kinesisanalytics:Describe*",
      "kinesisanalytics:Discover*",
      "kinesisanalytics:List*",
      "kinesisvideo:Describe*",
      "kinesisvideo:List*",
      "kms:Describe*",
      "kms:List*",
      "lakeformation:Describe*",
      "lakeformation:Get*",
      "lakeformation:List*",
      "lakeformation:Search*",
      "lambda:Get*",
      "lambda:List*",
      "ec2:Describe*"
    ]
    resources = ["*"]
  }
}

data "aws_iam_policy_document" "readonly_policy_part2" {
  statement {
    effect = "Allow"
    actions = [
      "launchwizard:Describe*",
      "launchwizard:GetWorkload",
      "launchwizard:List*",
      "license-manager:List*",
      "lightsail:Get*",
      "logs:Describe*",
      "logs:FilterLogEvents",
      "logs:List*",
      "logs:StartLiveTail",
      "logs:StartQuery",
      "logs:StopLiveTail",
      "logs:StopQuery",
      "logs:TestMetricFilter",
      "machinelearning:Describe*",
      "managedblockchain:GetMember",
      "managedblockchain:GetNetwork",
      "managedblockchain:GetNode",
      "managedblockchain:GetProposal",
      "managedblockchain:List*",
      "mediaconnect:Describe*",
      "mediaconnect:List*",
      "mediaconvert:List*",
      "medialive:Describe*",
      "medialive:Get*",
      "medialive:List*",
      "mediapackage-vod:Describe*",
      "mediapackage-vod:List*",
      "mediapackage:Describe*",
      "mediapackage:List*",
      "mediapackagev2:GetChannel",
      "mediapackagev2:GetChannelGroup",
      "mediapackagev2:GetChannelPolicy",
      "mediapackagev2:GetHeadObject",
      "mediapackagev2:GetOriginEndpoint",
      "mediapackagev2:GetOriginEndpointPolicy",
      "mediapackagev2:List*",
      "mediastore:Describe*",
      "mediastore:List*",
      "memorydb:Describe*",
      "memorydb:List*",
      "mq:Describe*",
      "mq:List*",
      "network-firewall:Describe*",
      "network-firewall:List*",
      "networkmanager:DescribeGlobalNetworks",
      "networkmanager:Get*",
      "networkmanager:List*",
      "nimble:List*",
      "notifications-contacts:List*",
      "notifications:Get*",
      "notifications:List*",
      "notifications:GetManagedNotificationEvent",
      "notifications:GetNotificationConfiguration",
      "notifications:GetNotificationsAccessForOrganization",
      "notifications:GetNotificationEvent",
      "notifications:List*",
      "one:ListUsers",
      "opsworks-cm:Describe*",
      "opsworks-cm:List*",
      "opsworks:Describe*",
      "organizations:Describe*",
      "organizations:List*",
      "outposts:List*",
      "personalize:Describe*",
      "personalize:List*",
      "pi:DescribeDimensionKeys",
      "pi:ListAvailableResourceDimensions",
      "pi:ListAvailableResourceMetrics",
      "pipes:DescribePipe",
      "pipes:ListPipes",
      "polly:Describe*",
      "polly:List*",
      "pricing:DescribeServices",
      "pricing:ListPriceLists",
      "qbusiness:List*",
      "ram:List*",
      "rbin:List*",
      "rds:Describe*",
      "rds:List*",
      "redshift-serverless:List*",
      "redshift:Describe*",
      "redshift:List*",
      "redshift:View*",
      "rekognition:Describe*",
      "rekognition:Detect*",
      "rekognition:List*",
      "resource-explorer-2:List*",
      "resource-groups:List*",
      "resource-groups:Search*",
      "robomaker:BatchDescribe*",
      "robomaker:Describe*",
      "robomaker:List*",
      "route53-recovery-cluster:Get*",
      "route53-recovery-cluster:List*",
      "route53-recovery-control-config:Describe*",
      "route53-recovery-control-config:Get*",
      "route53-recovery-control-config:List*",
      "route53-recovery-readiness:Get*",
      "route53-recovery-readiness:List*",
      "route53:Get*",
      "route53:List*",
      "route53:Test*",
      "route53domains:Check*",
      "route53domains:Get*",
      "route53domains:List*",
      "route53domains:View*",
      "route53profiles:Get*",
      "route53profiles:List*",
      "route53resolver:Get*",
      "route53resolver:List*",
      "rum:GetAppMonitor",
      "rum:GetAppMonitorData",
      "rum:ListAppMonitors",
      "s3-object-lambda:List*",
      "s3-outposts:Get*",
      "s3-outposts:List*",
      "s3:Describe*",
      "s3:List*",
      "s3:GetBucketLocation",
      "sagemaker:Describe*",
      "sagemaker:List*",
      "scheduler:List*",
      "schemas:Describe*",
      "schemas:Get*",
      "schemas:List*",
      "schemas:Search*",
      "sdb:List*",
      "sdb:Select*",
      "secretsmanager:GetResourcePolicy",
      "secretsmanager:List*",
      "securityhub:Describe*",
      "securityhub:List*",
      "securitylake:ListDataLakeExceptions",
      "securitylake:ListDataLakes",
      "securitylake:ListLogSources",
      "securitylake:ListSubscribers",
      "securitylake:ListTagsForResource",
      "serverlessrepo:Get*",
      "serverlessrepo:List*",
      "serverlessrepo:SearchApplications",
      "servicecatalog:Describe*",
      "servicecatalog:List*",
      "servicecatalog:Scan*",
      "servicecatalog:Search*",
      "servicediscovery:DiscoverInstances",
      "servicediscovery:DiscoverInstancesRevision",
      "servicediscovery:List*",
      "servicequotas:List*",
      "ses:Describe*",
      "ses:List*",
      "shield:Describe*",
      "shield:List*",
      "signer:DescribeSigningJob",
      "signer:List*",
      "signin:ListTrustedIdentityPropagationApplicationsForConsole",
      "sms-voice:Describe*",
      "sms-voice:List*",
      "snowball:Describe*",
      "snowball:List*",
      "sns:Check*",
      "sns:List*",
      "sqs:List*",
      "ssm-contacts:List*",
      "ssm-sap:List*",
      "ssm-quicksetup:List*",
      "ssm:List*",
      "sso-directory:List*",
      "sso:List*",
      "sso:Search*",
      "states:Describe*",
      "states:List*",
      "states:ValidateStateMachineDefinition",
      "storagegateway:Describe*",
      "storagegateway:List*",
      "sts:GetAccessKeyInfo",
      "sts:GetCallerIdentity",
      "sts:GetSessionToken",
      "support:Describe*",
      "support:SearchForCases",
      "tag:Describe*",
      "tag:Get*",
      "tax:ListTaxRegistrations",
      "timestream:Describe*",
      "tnb:List*",
      "transcribe:List*",
      "transfer:Describe*",
      "transfer:List*",
      "transfer:TestIdentityProvider",
      "translate:DescribeTextTranslationJob",
      "translate:ListParallelData",
      "translate:ListTerminologies",
      "translate:ListTextTranslationJobs",
      "trustedadvisor:Describe*",
      "trustedadvisor:List*",
      "verifiedpermissions:IsAuthorized",
      "verifiedpermissions:IsAuthorizedWithToken",
      "verifiedpermissions:List*",
      "vpc-lattice:Get*",
      "vpc-lattice:List*",
      "waf-regional:List*",
      "waf:List*",
      "wafv2:CheckCapacity",
      "wafv2:Describe*",
      "wafv2:List*",
      "wellarchitected:ExportLens",
      "wellarchitected:Get*",
      "wellarchitected:List*",
      "workdocs:CheckAlias",
      "workdocs:Describe*",
      "workmail:Describe*",
      "workmail:List*",
      "workmail:Search*",
      "workspaces-web:GetBrowserSettings",
      "workspaces-web:GetIdentityProvider",
      "workspaces-web:GetNetworkSettings",
      "workspaces-web:List*",
      "workspaces:Describe*"
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
      "logs:DeleteLogStream"
    ]
    resources = ["*"]
  }
} 
