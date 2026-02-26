#!/usr/bin/env bash
set -euo pipefail

# =========================
# 配置区
# =========================
LISTENER_ARN="arn:aws:elasticloadbalancing:us-east-1:992382367064:listener/app/sit-rds-medusa-alb/4fd4c4cf6bfc153a/9049d803e1ea8b5e"
AWS_PROFILE="${AWS_PROFILE:-}"

RULE_NAME=""
PRIORITY=""

usage() {
  cat <<EOF
用法:
  ./did-priority.sh --rule-name <Name标签> --priority <数字>

示例:
  ./did-priority.sh --rule-name did-test02 --priority 19
EOF
  exit 1
}

aws_elbv2() {
  if [[ -n "${AWS_PROFILE}" ]]; then
    aws --profile "${AWS_PROFILE}" elbv2 "$@"
  else
    aws elbv2 "$@"
  fi
}

check_deps() {
  command -v aws >/dev/null 2>&1 || { echo "错误：未安装 aws cli"; exit 1; }
  command -v jq  >/dev/null 2>&1 || { echo "错误：未安装 jq"; exit 1; }
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --rule-name)
        RULE_NAME="${2:-}"; shift 2 ;;
      --priority)
        PRIORITY="${2:-}"; shift 2 ;;
      -h|--help)
        usage ;;
      *)
        echo "未知参数: $1"
        usage ;;
    esac
  done

  [[ -n "$RULE_NAME" ]] || { echo "错误：--rule-name 不能为空"; usage; }
  [[ -n "$PRIORITY" ]] || { echo "错误：--priority 不能为空"; usage; }
  [[ "$PRIORITY" =~ ^[0-9]+$ ]] || { echo "错误：--priority 必须是数字"; exit 1; }
}

get_rules_json() {
  aws_elbv2 describe-rules --listener-arn "${LISTENER_ARN}"
}

get_rule_names_json() {
  local rules_json="$1"
  local rule_arns=()
  mapfile -t rule_arns < <(echo "$rules_json" | jq -r '.Rules[].RuleArn')

  if [[ ${#rule_arns[@]} -eq 0 ]]; then
    echo '{}'
    return
  fi

  local tags_json
  tags_json="$(aws_elbv2 describe-tags --resource-arns "${rule_arns[@]}")"

  echo "$tags_json" | jq '
    reduce .TagDescriptions[] as $td ({};
      .[$td.ResourceArn] = (
        ($td.Tags // [])
        | map(select(.Key == "Name") | .Value)
        | .[0] // ""
      )
    )'
}

find_rule_arn_by_name() {
  local target_name="$1"
  local rules_json="$2"
  local names_json="$3"

  while IFS= read -r arn; do
    local n
    n="$(echo "$names_json" | jq -r --arg arn "$arn" '.[$arn] // ""')"
    if [[ "$n" == "$target_name" ]]; then
      echo "$arn"
      return 0
    fi
  done < <(echo "$rules_json" | jq -r '.Rules[].RuleArn')
}

set_rule_priority() {
  local rule_arn="$1"
  local new_priority="$2"

  aws_elbv2 set-rule-priorities \
    --rule-priorities "RuleArn=${rule_arn},Priority=${new_priority}" >/dev/null
}

print_result_summary() {
  local rule_arn="$1"
  local rule_json
  rule_json="$(aws_elbv2 describe-rules --rule-arns "$rule_arn" | jq -c '.Rules[0]')"

  local priority
  priority="$(echo "$rule_json" | jq -r '.Priority')"

  echo "变更成功"
  echo "RuleArn: $rule_arn"
  echo "Priority: $priority"
}

main() {
  check_deps
  parse_args "$@"

  local rules_json names_json rule_arn
  rules_json="$(get_rules_json)"
  names_json="$(get_rule_names_json "$rules_json")"
  rule_arn="$(find_rule_arn_by_name "$RULE_NAME" "$rules_json" "$names_json" || true)"

  if [[ -z "${rule_arn:-}" ]]; then
    echo "错误：未找到 Name 标签为 [$RULE_NAME] 的规则"
    exit 1
  fi

  set_rule_priority "$rule_arn" "$PRIORITY"
  print_result_summary "$rule_arn"
}

main "$@"
