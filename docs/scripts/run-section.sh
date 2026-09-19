#!/usr/bin/env bash
# Run one section of this repo with Docker only (no local JDK 25 / Maven needed).
#
#   docs/scripts/run-section.sh <project-dir> [sql-script]
#
# Examples
#   docs/scripts/run-section.sh section3/springsecsection3                      # no database needed
#   docs/scripts/run-section.sh section_12/springsecsection_12                  # loads that section's sql/scripts.sql
#   docs/scripts/run-section.sh section_16/authserver                           # port 9000
#
# KEEP_DB=1 reuses the running MySQL container instead of recreating it.
# APP_NAME=<name> renames the app container; extra environment variables can be passed as APP_ENV="-e JWK_SET_URI=http://as16:9000/oauth2/jwks".
# Stop everything with:  docker rm -f secmysql secapp; docker network rm secnet
set -euo pipefail

PROJECT="${1:?usage: run-section.sh <project-dir> [sql-script]}"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SRC="$ROOT/$PROJECT"
SQL="${2:-$SRC/src/main/resources/sql/scripts.sql}"
APP_NAME="${APP_NAME:-secapp}"   # container name; set it to run two apps side by side
PORT=8080; [[ "$PROJECT" == *authserver* ]] && PORT=9000
export MSYS_NO_PATHCONV=1   # Git Bash on Windows: stop it rewriting /app paths
MOUNT="$SRC"; command -v cygpath >/dev/null && MOUNT="$(cygpath -w "$SRC")"

docker network create secnet >/dev/null 2>&1 || true
docker volume create m2sec >/dev/null

if [[ "${KEEP_DB:-0}" == 1 ]] && docker ps --format "{{.Names}}" | grep -qx secmysql; then
  echo "KEEP_DB=1: reusing the running secmysql container"
elif [[ -f "$SQL" ]] && grep -q -i "create table" "$SQL"; then
  docker rm -f secmysql >/dev/null 2>&1 || true
  docker run -d --name secmysql --network secnet -p 3306:3306 \
    -e MYSQL_ROOT_PASSWORD=root -e MYSQL_DATABASE=eazybank mysql:8.4 >/dev/null
  echo "waiting for MySQL..."
  until docker exec secmysql mysqladmin ping -uroot -proot --silent 2>/dev/null; do sleep 3; done
  # the leading "drop table" lines fail on an empty database, so skip them
  grep -v -E '^drop table' "$SQL" | docker exec -i secmysql mysql -uroot -proot eazybank
  echo "database loaded from $SQL"
fi

docker rm -f "$APP_NAME" >/dev/null 2>&1 || true
# shellcheck disable=SC2086
docker run -d --name "$APP_NAME" --network secnet -p "$PORT:$PORT" \
  -e DATABASE_HOST=secmysql -e SPRING_SECURITY_LOG_LEVEL=INFO ${APP_ENV:-} \
  -v "$MOUNT:/app" -v m2sec:/root/.m2 -w /app \
  maven:3.9-eclipse-temurin-25 mvn -q -DskipTests spring-boot:run >/dev/null
echo "building and starting (first run downloads dependencies, ~2 min). Follow with: docker logs -f $APP_NAME"
echo "then open http://localhost:$PORT"
