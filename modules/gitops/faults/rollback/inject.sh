#!/bin/bash
# gitops-4 rollback — inject. 직접 실행하지 말고 common/inject.sh 로 호출한다.
# 영향 범위: 내 Fork 오늘 브랜치의 운영 값·앱 목록(gitops/apps/templates/prod.yaml), 그 결과로 app 네임스페이스의 샘플 앱
source "$(dirname "$(readlink -f "$0")")/../../lib.sh"
V=$(pick_variant 2); base_save
case $V in
  1) # 잘못된 values 커밋: 릴리스 v2(정상) 바로 뒤에 "캐시 주소 정리" 커밋이 없는 서비스 이름(opslab-redis)을 넣었다 → /cache 500
     release_v2
     commit_append "$PV" "캐시 주소를 서비스 이름으로 정리" $'redis:\n  host: opslab-redis' ;;
  2) # App of Apps 에서 자식 앱 삭제 커밋: "정리" 커밋이 앱 목록에서 운영 앱 정의를 지웠다 → 루트 앱이 opslab-prod 를 지우고(prune),
     #    finalizer 때문에 운영 앱이 만든 Deployment·Service 까지 함께 지워진다 → 사이트 다운(503)
     gh_rm "$R" "$B" "$PA" "정리: 앱 목록에서 중복 정의 삭제" ;;
esac
kick
record $V
