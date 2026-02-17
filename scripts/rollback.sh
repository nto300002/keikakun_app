#!/bin/bash
# Keikakun API ロールバックスクリプト
#
# 使用方法:
#   ./scripts/rollback.sh <commit_hash> [project_id]
#
# 例:
#   ./scripts/rollback.sh 6831359
#   ./scripts/rollback.sh 6831359 my-gcp-project

set -e

COMMIT_HASH=$1
PROJECT_ID=${2:-$GCP_PROJECT_ID}
REGION="asia-northeast1"
SERVICE_NAME="k-back"

# カラー出力用
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 使用方法チェック
if [ -z "$COMMIT_HASH" ]; then
  echo -e "${RED}Error: Commit hash is required${NC}"
  echo ""
  echo "Usage: $0 <commit_hash> [project_id]"
  echo ""
  echo "Examples:"
  echo "  $0 6831359"
  echo "  $0 6831359 my-gcp-project"
  echo ""
  echo -e "${BLUE}Recent commits:${NC}"
  git log --oneline -10
  exit 1
fi

# PROJECT_IDチェック
if [ -z "$PROJECT_ID" ]; then
  echo -e "${RED}Error: GCP Project ID is required${NC}"
  echo ""
  echo "Please specify project ID by either:"
  echo "  1. Pass as second argument: $0 $COMMIT_HASH <project_id>"
  echo "  2. Set GCP_PROJECT_ID environment variable: export GCP_PROJECT_ID=<project_id>"
  exit 1
fi

# 確認プロンプト
echo -e "${BLUE}============================================${NC}"
echo -e "${BLUE}Keikakun API Rollback${NC}"
echo -e "${BLUE}============================================${NC}"
echo -e "Target commit:  ${GREEN}$COMMIT_HASH${NC}"
echo -e "Service:        ${GREEN}$SERVICE_NAME${NC}"
echo -e "Region:         ${GREEN}$REGION${NC}"
echo -e "Project:        ${GREEN}$PROJECT_ID${NC}"
echo ""

# Git履歴との照合
echo -e "${BLUE}Git commit info:${NC}"
if git log --oneline | grep -q "^$COMMIT_HASH"; then
  git log --oneline -1 $COMMIT_HASH
else
  echo -e "${YELLOW}Warning: Commit hash not found in local Git history${NC}"
  echo "This may be from a different branch or older commit."
fi
echo ""

read -p "Are you sure you want to rollback? (yes/no): " confirm

if [ "$confirm" != "yes" ]; then
  echo -e "${YELLOW}Rollback cancelled.${NC}"
  exit 0
fi

# イメージの存在確認
echo ""
echo -e "${BLUE}Checking if image exists...${NC}"
IMAGE_URI="asia-northeast1-docker.pkg.dev/$PROJECT_ID/k-back-repo/k-back:$COMMIT_HASH"

if ! gcloud artifacts docker images describe "$IMAGE_URI" --project=$PROJECT_ID > /dev/null 2>&1; then
  echo -e "${RED}Error: Image not found: $IMAGE_URI${NC}"
  echo ""
  echo -e "${BLUE}Available images (last 10):${NC}"
  gcloud artifacts docker images list \
    asia-northeast1-docker.pkg.dev/$PROJECT_ID/k-back-repo/k-back \
    --limit=10 \
    --project=$PROJECT_ID
  exit 1
fi

echo -e "${GREEN}✓ Image found${NC}"

# 現在のリビジョンを確認（バックアップ情報として）
echo ""
echo -e "${BLUE}Current revision:${NC}"
CURRENT_REVISION=$(gcloud run services describe $SERVICE_NAME \
  --region=$REGION \
  --project=$PROJECT_ID \
  --format="value(status.latestCreatedRevisionName)")
echo -e "  ${YELLOW}$CURRENT_REVISION${NC}"
echo ""
echo -e "${YELLOW}Note: You can rollback to this revision later using:${NC}"
echo -e "${YELLOW}  gcloud run services update-traffic $SERVICE_NAME --to-revisions=$CURRENT_REVISION=100 --region=$REGION${NC}"

# ロールバック実行
echo ""
echo -e "${BLUE}Rolling back to commit: $COMMIT_HASH${NC}"
echo -e "${BLUE}Image: $IMAGE_URI${NC}"
echo ""

gcloud run deploy $SERVICE_NAME \
  --image=$IMAGE_URI \
  --region=$REGION \
  --project=$PROJECT_ID

# 結果確認
echo ""
echo -e "${GREEN}============================================${NC}"
echo -e "${GREEN}Rollback completed successfully!${NC}"
echo -e "${GREEN}============================================${NC}"
echo ""

# サービスURL取得
echo -e "${BLUE}Service URL:${NC}"
SERVICE_URL=$(gcloud run services describe $SERVICE_NAME \
  --region=$REGION \
  --project=$PROJECT_ID \
  --format="value(status.url)")
echo -e "  ${GREEN}$SERVICE_URL${NC}"

# ヘルスチェック
echo ""
echo -e "${BLUE}Checking health...${NC}"
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "$SERVICE_URL/" || echo "000")

if [ "$HTTP_CODE" = "200" ]; then
  echo -e "${GREEN}✅ Health check passed! (HTTP $HTTP_CODE)${NC}"
else
  echo -e "${RED}⚠️  Health check failed (HTTP $HTTP_CODE) - please verify manually${NC}"
  echo -e "URL: $SERVICE_URL"
fi

# 新しいリビジョン情報
echo ""
echo -e "${BLUE}New revision:${NC}"
NEW_REVISION=$(gcloud run services describe $SERVICE_NAME \
  --region=$REGION \
  --project=$PROJECT_ID \
  --format="value(status.latestCreatedRevisionName)")
echo -e "  ${GREEN}$NEW_REVISION${NC}"

# ログ確認コマンドのヒント
echo ""
echo -e "${BLUE}To view logs:${NC}"
echo -e "  gcloud logging read 'resource.type=cloud_run_revision AND resource.labels.service_name=$SERVICE_NAME' --limit=50 --project=$PROJECT_ID"
