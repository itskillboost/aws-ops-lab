#!/bin/bash
# image 정리 훅 — common/cleanup.sh 가 스택 삭제 전에 부른다. 수강생이 CLI·콘솔로 만든 것과 장애 실습이 남긴 것을 지운다.
# · 파이프라인, CodeBuild 프로젝트 3개, GitHub 연결(<학번>-image-github), ECR 저장소(이미지째), 산출물 버킷 내용,
#   CodeBuild 로그 그룹, 빌드 역할의 거부 정책·콘솔이 붙인 정책, 장애용 시크릿
set -uo pipefail
: "${SID:?}"; export AWS_REGION="${AWS_REGION:-ap-northeast-2}"
aws codepipeline get-pipeline --name "$SID-image-pipeline" >/dev/null 2>&1 && aws codepipeline delete-pipeline --name "$SID-image-pipeline" && echo "  파이프라인 삭제"
for p in build scan deploy; do
  [ "$(aws codebuild batch-get-projects --names "$SID-image-$p" --query 'length(projects)' --output text 2>/dev/null)" = 1 ] \
    && aws codebuild delete-project --name "$SID-image-$p" >/dev/null && echo "  CodeBuild 프로젝트 삭제: $SID-image-$p"
  aws logs delete-log-group --log-group-name "/aws/codebuild/$SID-image-$p" 2>/dev/null && echo "  로그 그룹 삭제: /aws/codebuild/$SID-image-$p"
done
for c in $(aws codeconnections list-connections --query "Connections[?ConnectionName=='$SID-image-github'].ConnectionArn" --output text 2>/dev/null); do
  aws codeconnections delete-connection --connection-arn "$c" >/dev/null && echo "  GitHub 연결 삭제"; done
aws ecr delete-repository --repository-name "$SID-image-app" --force >/dev/null 2>&1 && echo "  ECR 저장소 삭제: $SID-image-app (이미지 포함)"
B="$SID-image-artifacts-$(aws sts get-caller-identity --query Account --output text)"
if aws s3api head-bucket --bucket "$B" 2>/dev/null; then
  aws s3 rm "s3://$B" --recursive --quiet && echo "  산출물 버킷 비움: $B (버킷은 스택이 삭제)"
fi
aws secretsmanager delete-secret --secret-id "$SID-image-old-token" --force-delete-without-recovery >/dev/null 2>&1 && echo "  장애용 시크릿 삭제"
R="$SID-image-build-role"
aws iam delete-role-policy --role-name "$R" --policy-name opslab-fault-deny 2>/dev/null && echo "  거부 정책 삭제: $R"
# 콘솔에서 CodeBuild 프로젝트를 만들며 "서비스 역할 수정"을 켜 두면 콘솔이 역할에 정책을 붙인다 → 역할(스택) 삭제 전에 뗀다
for p in $(aws iam list-attached-role-policies --role-name "$R" --query "AttachedPolicies[?starts_with(PolicyName,'CodeBuildBasePolicy-')].PolicyArn" --output text 2>/dev/null); do
  aws iam detach-role-policy --role-name "$R" --policy-arn "$p"
  for v in $(aws iam list-policy-versions --policy-arn "$p" --query 'Versions[?!IsDefaultVersion].VersionId' --output text 2>/dev/null); do aws iam delete-policy-version --policy-arn "$p" --version-id "$v"; done
  aws iam delete-policy --policy-arn "$p" 2>/dev/null && echo "  콘솔이 붙인 정책 삭제: ${p##*/}"
done
exit 0
