#!/usr/bin/env bash
set -euo pipefail

# =========================
# 配置区
# =========================
LISTENER_ARN="arn:aws:elasticloadbalancing:us-east-1:992382714390:listener/app/mpaasgw/25907e5a3a778b9b/a4c63ea23ad0a4f7"
DEFAULT_HTTP_HEADER_NAME="did"
AWS_PROFILE="${AWS_PROFILE:-}"

ACTION=""
HEADER_VALUE=""
RULE_NAME=""
PRIORITY=""

usage() {
  cat <<EOF
用法:
  ./did-modify.sh --action add|delete --header-value <值> --rule-name <Name标签> --priority <数字>

示例:
  ./did-modify.sh --action add --header-value cfjhweru9892u1ihnu9fcdw --rule-name did-test02 --priority 20
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
      --action)
        ACTION="${2:-}"; shift 2 ;;
      --header-value)
        HEADER_VALUE="${2:-}"; shift 2 ;;
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

  [[ -n "$ACTION" ]] || { echo "错误：--action 不能为空"; usage; }
  [[ "$ACTION" == "add" || "$ACTION" == "delete" ]] || { echo "错误：--action 只能是 add 或 delete"; usage; }
  [[ -n "$HEADER_VALUE" ]] || { echo "错误：--header-value 不能为空"; usage; }
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

modify_http_header_condition_value() {
  local rule_arn="$1"
  local op="$2"           # add / delete
  local header_value="$3"

  local rule_json
  rule_json="$(aws_elbv2 describe-rules --rule-arns "$rule_arn" | jq -c '.Rules[0]')"

  local p
  p="$(echo "$rule_json" | jq -r '.Priority')"
  if [[ "$p" == "default" ]]; then
    echo "错误：默认规则（default）不支持修改条件。"
    exit 1
  fi

  local has_http_header
  has_http_header="$(echo "$rule_json" | jq '[.Conditions[] | select(.Field=="http-header")] | length')"

  local new_conditions_json
  if [[ "$has_http_header" -gt 0 ]]; then
    if [[ "$op" == "add" ]]; then
      new_conditions_json="$(echo "$rule_json" | jq --arg v "$header_value" '
        .Conditions
        | map(
            if .Field == "http-header" then
              .HttpHeaderConfig.Values = (((.HttpHeaderConfig.Values // []) + [$v]) | unique)
            else .
            end
          )
      ')"
    else
      new_conditions_json="$(echo "$rule_json" | jq --arg v "$header_value" '
        .Conditions
        | map(
            if .Field == "http-header" then
              .HttpHeaderConfig.Values = ((.HttpHeaderConfig.Values // []) | map(select(. != $v)))
            else .
            end
          )
      ')"

      local remaining
      remaining="$(echo "$new_conditions_json" | jq '[.[] | select(.Field=="http-header") | .HttpHeaderConfig.Values[]?] | length')"
      if [[ "$remaining" -eq 0 ]]; then
        echo "错误：删除后 http-header 条件值为空，AWS 不允许空值。"
        exit 1
      fi
    fi
  else
    if [[ "$op" == "delete" ]]; then
      echo "错误：该规则没有 http-header 条件，无法删除。"
      exit 1
    fi

    new_conditions_json="$(echo "$rule_json" | jq \
      --arg hn "$DEFAULT_HTTP_HEADER_NAME" \
      --arg v "$header_value" '
      .Conditions + [{
        "Field": "http-header",
        "HttpHeaderConfig": {
          "HttpHeaderName": $hn,
          "Values": [$v]
        }
      }]
    ')"
  fi

  local tmpf
  tmpf="$(mktemp)"
  echo "$new_conditions_json" > "$tmpf"
  aws_elbv2 modify-rule --rule-arn "$rule_arn" --conditions "file://$tmpf" >/dev/null
  rm -f "$tmpf"
}

set_rule_priority() {
  local rule_arn="$1"
  local new_priority="$2"

  aws_elbv2 set-rule-priorities \
    --rule-priorities "RuleArn=${rule_arn},Priority=${new_priority}" >/dev/null
}

# 打印简化结果（给 Flask 调用看日志很有用）
print_result_summary() {
  local rule_arn="$1"
  local rule_json
  rule_json="$(aws_elbv2 describe-rules --rule-arns "$rule_arn" | jq -c '.Rules[0]')"

  local priority conds
  priority="$(echo "$rule_json" | jq -r '.Priority')"
  conds="$(echo "$rule_json" | jq -r '
    (.Conditions // [])
    | map(
        if .Field=="http-header" then
          "http-header(" + (.HttpHeaderConfig.HttpHeaderName // "") + ")=" + ((.HttpHeaderConfig.Values // [])|join(","))
        else
          .Field
        end
      ) | join(" ; ")
  ')"

  echo "变更成功"
  echo "RuleArn: $rule_arn"
  echo "Priority: $priority"
  echo "Conditions: $conds"
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

  modify_http_header_condition_value "$rule_arn" "$ACTION" "$HEADER_VALUE"
  set_rule_priority "$rule_arn" "$PRIORITY"
  print_result_summary "$rule_arn"
}

main "$@"
