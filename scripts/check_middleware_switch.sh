#!/usr/bin/env bash
set -euo pipefail

# ================== 可配置区 ==================
DB_HOST="cirrus-prod-sofa-mysql.cvyui42uejzr.us-east-1.rds.amazonaws.com"
DB_USER="BE-Readonly"
DB_PASS='Y8*mN2#pQ5!zJ1'
DB_PORT="3306"
# ============================================

need() { command -v "$1" >/dev/null 2>&1 || { echo "缺少依赖：$1"; exit 1; }; }
need mysql

ts() { date "+%F %T"; }
hr() { printf "\n%s\n" "------------------------------------------------------------"; }

run_sql() {
  local title="$1"
  local dbhint="$2"   # 只是用来显示提示，不影响执行
  local sql="$3"

  echo
  echo "MySQL [${dbhint}]> ${sql}"
  MYSQL_PWD="$DB_PASS" mysql \
    -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" \
    --connect-timeout=5 \
    --default-character-set=utf8mb4 \
    -e "$sql"
}


echo "[$(ts)] Start DB checks on ${DB_HOST}:${DB_PORT} (user=${DB_USER})"

# 1) 检查 group_id 是否为 default
run_sql "Check group_id" "confdb" \
"SELECT group_id FROM confdb.notify_resource;"

# 2) 检查 mq 消息情况（四条 count）
run_sql "Check MQ msg count: zlqba-mq-msgbroker-0" "msgdb" \
"SELECT COUNT(*) AS cnt FROM msgdb.notify_bytes_msg_normal WHERE server_tag='zlqba-mq-msgbroker-0';"

run_sql "Check MQ msg count: zlqba-mq-msgbroker-1" "msgdb" \
"SELECT COUNT(*) AS cnt FROM msgdb.notify_bytes_msg_normal WHERE server_tag='zlqba-mq-msgbroker-1';"

run_sql "Check MQ msg count: zlqbb-mq-msgbroker-0" "msgdb" \
"SELECT COUNT(*) AS cnt FROM msgdb.notify_bytes_msg_normal WHERE server_tag='zlqbb-mq-msgbroker-0';"

run_sql "Check MQ msg count: zlqbb-mq-msgbroker-1" "msgdb" \
"SELECT COUNT(*) AS cnt FROM msgdb.notify_bytes_msg_normal WHERE server_tag='zlqbb-mq-msgbroker-1';"

# 3) 检查 antscheduler 是否生效
run_sql "Check antscheduler.config" "antscheduler" \
"SELECT * FROM antscheduler.config;"

hr
echo "[$(ts)] Done."

