#!/usr/bin/env python3
"""Exercise source-qualified CloudFormation collector permissions."""
import fnmatch
import json
import re
import runpy
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TEMPLATE = json.loads((ROOT / "aws-integration-setup/cloudformation/nullify-cloudformation-template.json").read_text())


def render(value, parameters, conditions):
    if isinstance(value, list):
        return [render(item, parameters, conditions) for item in value]
    if not isinstance(value, dict):
        return value
    if isinstance(value.get("Condition"), str):
        return conditions[value["Condition"]]
    if "Fn::Equals" in value:
        left, right = render(value["Fn::Equals"], parameters, conditions)
        return left == right
    if "Fn::Not" in value:
        return not render(value["Fn::Not"][0], parameters, conditions)
    if "Fn::And" in value:
        return all(render(value["Fn::And"], parameters, conditions))
    if "Ref" in value:
        return parameters[value["Ref"]]
    if "Fn::Sub" in value:
        return re.sub(r"\$\{([^}]+)\}", lambda match: parameters[match[1]], value["Fn::Sub"])
    if "Fn::If" in value:
        condition, yes, no = value["Fn::If"]
        return render(yes if conditions[condition] else no, parameters, conditions)
    return {key: render(item, parameters, conditions) for key, item in value.items()}


class ConnectorPolicyProbeScope(unittest.TestCase):
    def test_drift_normalization_preserves_role_and_account_boundaries(self):
        drift = runpy.run_path(str(ROOT / "scripts/check_iam_policy_drift.py"))
        cfn = drift["_norm_cfn_value"]({"Fn::Sub": "arn:${AWS::Partition}:iam::${AWS::AccountId}:role/AWSIntegration-${CustomerName}-NullifyReadOnlyRole"})
        resource = "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:role/${local.role_name}"
        locals_ = {"role_name": "${local.role_name_prefix}-NullifyReadOnlyRole", "role_name_prefix": "AWSIntegration-${var.customer_name}"}
        normalize = drift["_norm_tf_value"]
        self.assertEqual(cfn, normalize(resource, locals_))
        self.assertNotEqual(cfn, normalize(resource, {**locals_, "role_name": "another-role"}))
        self.assertNotEqual(cfn, normalize(resource.replace("${data.aws_caller_identity.current.account_id}", "999999999999"), locals_))
        with self.assertRaises(SystemExit):
            normalize(resource, {"role_name": "${local.role_name}"})

    def test_only_the_connector_role_can_be_simulated(self):
        statements = TEMPLATE["Resources"]["ReadOnlyAccessPolicy2"]["Properties"]["PolicyDocument"]["Statement"]
        grants = [item for item in statements if "iam:SimulatePrincipalPolicy" in item["Action"]]
        self.assertEqual(len(grants), 1)
        for partition in ("aws", "aws-us-gov", "aws-cn"):
            parameters = {"AWS::Partition": partition, "AWS::AccountId": "123456789012", "CustomerName": "acme"}
            grant = render(grants[0], parameters, {})
            own = f"arn:{partition}:iam::123456789012:role/AWSIntegration-acme-NullifyReadOnlyRole"
            self.assertEqual(grant["Resource"], own)
            self.assertEqual(grant["Action"], ["iam:SimulatePrincipalPolicy"])
            self.assertEqual(grant["Effect"], "Allow")
            for foreign in (own.replace("acme", "other"), own.replace("123456789012", "999999999999")):
                self.assertFalse(fnmatch.fnmatchcase(foreign, grant["Resource"]))

    def test_terraform_keeps_the_same_self_scope(self):
        for version in ("terraform", "terraform-v6"):
            source = (ROOT / f"aws-integration-setup/{version}/modules/nullify-aws-integration/data.tf").read_text()
            statements = re.findall(r"statement \{(.*?)\n  \}", source, re.S)
            grants = [item for item in statements if '"iam:SimulatePrincipalPolicy"' in item]
            self.assertEqual(len(grants), 1)
            self.assertIn('resources = ["arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:role/${local.role_name}"]', grants[0])
            self.assertIn('actions   = ["iam:SimulatePrincipalPolicy"]', grants[0])


class CollectorUploadScope(unittest.TestCase):
    def test_two_sources_never_grant_sibling_uploads(self):
        policy = TEMPLATE["Resources"]["S3AccessPolicy"]["Properties"]["PolicyDocument"]
        for source in ("GitHub-1", "GitHub-2"):
            for access_point in (False, True):
                with self.subTest(source=source, access_point=access_point):
                    parameters = {
                        "NullifyS3Bucket": "nullify-collector-uploads",
                        "NullifyS3AccessPointArn": "arn:aws:s3:eu-central-1:111122223333:accesspoint/uploads",
                        "CollectorUploadPrefix": f"k8s-collector/{source}/",
                    }
                    rendered = render(policy, parameters, {"S3AccessPointProvided": access_point})
                    grants = [statement for statement in rendered["Statement"] if "s3:PutObject" in statement["Action"]]
                    self.assertTrue(grants)
                    for target, expected in (("GitHub-1", source == "GitHub-1"), ("GitHub-2", source == "GitHub-2"), ("k8s-collector", False)):
                        objects = [f"arn:aws:s3:::nullify-collector-uploads/k8s-collector/{target}/prod-data.json"]
                        if access_point:
                            objects.append(f"{parameters['NullifyS3AccessPointArn']}/object/k8s-collector/{target}/prod-data.json")
                        for obj in objects:
                            allowed = any(fnmatch.fnmatchcase(obj, resource) for grant in grants for resource in grant["Resource"])
                            self.assertEqual(allowed, expected, obj)
                    listing = next(statement for statement in rendered["Statement"] if "s3:ListBucket" in statement["Action"])
                    self.assertEqual(listing["Condition"]["StringLike"]["s3:prefix"], [f"k8s-collector/{source}/*"])

    def test_shared_and_malformed_prefixes_are_rejected(self):
        pattern = TEMPLATE["Parameters"]["CollectorUploadPrefix"]["AllowedPattern"]
        self.assertRegex("k8s-collector/GitHub-1/", pattern)
        for value in ("k8s-collector", "k8s-collector/k8s-collector/", "k8s-collector/*/", "k8s-collector/../", "k8s-collector/GitHub-1/other/"):
            self.assertIsNone(re.fullmatch(pattern, value), value)
        rule = TEMPLATE["Rules"]["CollectorPrefixRequired"]
        for enabled, prefix, accepted in (("true", "", False), ("true", "k8s-collector/GitHub-1/", True), ("false", "", True)):
            parameters = {"EnableEKSIntegration": enabled, "CollectorUploadPrefix": prefix}
            condition = render(rule["RuleCondition"], parameters, {})
            assertions = all(render(assertion["Assert"], parameters, {}) for assertion in rule["Assertions"])
            self.assertEqual(not condition or assertions, accepted)
        self.assertEqual(TEMPLATE["Resources"]["S3AccessPolicy"]["Condition"], "CollectorUploadsEnabled")
        self.assertEqual(TEMPLATE["Resources"]["IAMViewOnlyRole"]["Properties"]["ManagedPolicyArns"]["Fn::If"][0], "CollectorUploadsEnabled")


class CollectorSetupWizard(unittest.TestCase):
    def run_wizard(self, method, prefix="k8s-collector/GitHub-1/"):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        root = Path(temporary.name)
        script = root / "aws-integration-setup/scripts/setup-aws-integration.sh"
        script.parent.mkdir(parents=True)
        shutil.copyfile(ROOT / "aws-integration-setup/scripts/setup-aws-integration.sh", script)
        (root / "aws-integration-setup/terraform").mkdir(parents=True)
        (root / "helm-charts/nullify-k8s-collector").mkdir(parents=True)
        values = ["acme", "example-external-id-12345", "arn:aws:iam::123456789012:role/NullifyReadOnly", "eu-central-1", "example-uploads", "arn:aws:kms:eu-central-1:111122223333:key/00000000-0000-0000-0000-000000000000", "n" if method == "helm" else "y", prefix]
        if method == "cloudformation":
            values += ["oidc.eks.eu-central-1.amazonaws.com/id/example"]
        elif method == "terraform":
            values += ["arn:aws:eks:eu-central-1:123456789012:cluster/prod", ""]
        else:
            values += ["prod"]
        result = subprocess.run(["bash", str(script), "--method", method], input="\n".join(values)+"\n", capture_output=True, text=True, timeout=10)
        return root, result

    def test_cloudformation_preserves_the_source_prefix(self):
        _, result = self.run_wizard("cloudformation")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("ParameterKey=CollectorUploadPrefix,ParameterValue=k8s-collector/GitHub-1/", result.stdout)

    def test_terraform_preserves_the_source_prefix(self):
        root, result = self.run_wizard("terraform")
        self.assertEqual(result.returncode, 0, result.stderr)
        generated = (root / "aws-integration-setup/terraform/terraform.tfvars").read_text()
        self.assertIn('collector_upload_prefix = "k8s-collector/GitHub-1/"', generated)

    def test_helm_writes_current_chart_keys_and_the_actual_cluster(self):
        root, result = self.run_wizard("helm")
        self.assertEqual(result.returncode, 0, result.stderr)
        generated = (root / "helm-charts/nullify-k8s-collector/values-custom.yaml").read_text()
        self.assertIn('clusterName: "prod"', generated)
        self.assertIn('  s3:\n    bucket: "example-uploads"\n    keyPrefix: "k8s-collector/GitHub-1/"', generated)
        self.assertIn('  kms:\n    keyArn:', generated)
        self.assertNotIn("s3BucketName:", generated)
        self.assertNotIn("kmsKeyArn:", generated)

    def test_unbound_and_malformed_prefixes_fail_before_configuration(self):
        for prefix in ("", "k8s-collector/", "k8s-collector/k8s-collector/", "k8s-collector/*/", "k8s-collector/../"):
            with self.subTest(prefix=prefix):
                root, result = self.run_wizard("cloudformation", prefix)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("Copy the source-qualified collectorUploadPrefix", result.stdout)
                self.assertFalse((root / "helm-charts/nullify-k8s-collector/values-custom.yaml").exists())


if __name__ == "__main__":
    unittest.main()
