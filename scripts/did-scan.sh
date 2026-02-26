#!/usr/bin/env bash
set -euo pipefail

# =========================
# 配置区
# =========================
LISTENER_ARN="arn:aws:elasticloadbalancing:us-east-1:992382714390:listener/app/mpaasgw/25907e5a3a778b9b/a4c63ea23ad0a4f7"
AWS_PROFILE="${AWS_PROFILE:-}"

# 输出模式: table | pretty | json
OUTPUT_MODE="table"

# 筛选参数
FILTER_RULE_NAME=""
FILTER_NAME_LIKE=""
FILTER_PRIORITY=""
FILTER_HEADER_NAME=""

usage() {
  cat <<EOF
用法:
  ./did-scan.sh [选项]

输出模式:
  --json                输出 JSON（给 Flask/前端）
  --pretty              人类友好多行块状输出（推荐）

筛选:
  --rule-name <名称>    按 Name 标签精确匹配
  --name-like <关键字>  按 Name 标签模糊匹配
  --priority <优先级>   按优先级筛选（如 12）
  --header-name <名称>  仅显示包含该 http-header 名称的规则（如 did）

帮助:
  -h, --help

示例:
  ./did-scan.sh
  ./did-scan.sh --pretty
  ./did-scan.sh --pretty --name-like did-
  ./did-scan.sh --pretty --priority 12
  ./did-scan.sh --pretty --header-name did
  ./did-scan.sh --json
EOF
  exit 0
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
      --json)
        OUTPUT_MODE="json"; shift ;;
      --pretty)
        OUTPUT_MODE="pretty"; shift ;;
      --rule-name)
        FILTER_RULE_NAME="${2:-}"; shift 2 ;;
      --name-like)
        FILTER_NAME_LIKE="${2:-}"; shift 2 ;;
      --priority)
        FILTER_PRIORITY="${2:-}"; shift 2 ;;
      --header-name)
        FILTER_HEADER_NAME="${2:-}"; shift 2 ;;
      -h|--help)
        usage ;;
      *)
        echo "未知参数: $1"
        usage ;;
    esac
  done
}

short_rule_id() {
  local rule_arn="$1"
  echo "${rule_arn##*/}"
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

# 生成结构化规则 JSON（统一供 table/pretty/json 三种输出使用）
build_structured_rules_json() {
  local rules_json="$1"
  local names_json="$2"

  jq -n \
    --argjson rules "$(echo "$rules_json" | jq '.Rules')" \
    --argjson names "$names_json" '
    $rules
    | sort_by(if .Priority == "default" then 999999 else (.Priority|tonumber) end)
    | map(
        . as $r
        | {
            priority: $r.Priority,
            name: ($names[$r.RuleArn] // ""),
            ruleArn: $r.RuleArn,
            isDefault: ($r.Priority == "default"),
            conditions: (
              ($r.Conditions // []) | map(
                if .Field == "host-header" then
                  {
                    field: .Field,
                    values: (.HostHeaderConfig.Values // []),
                    text: ("host-header=" + ((.HostHeaderConfig.Values // []) | join(",")))
                  }
                elif .Field == "path-pattern" then
                  {
                    field: .Field,
                    values: (.PathPatternConfig.Values // []),
                    text: ("path-pattern=" + ((.PathPatternConfig.Values // []) | join(",")))
                  }
                elif .Field == "http-header" then
                  {
                    field: .Field,
                    httpHeaderName: (.HttpHeaderConfig.HttpHeaderName // ""),
                    values: (.HttpHeaderConfig.Values // []),
                    text: ("http-header(" + (.HttpHeaderConfig.HttpHeaderName // "") + ")=" + ((.HttpHeaderConfig.Values // []) | join(",")))
                  }
                elif .Field == "http-request-method" then
                  {
                    field: .Field,
                    values: (.HttpRequestMethodConfig.Values // []),
                    text: ("method=" + ((.HttpRequestMethodConfig.Values // []) | join(",")))
                  }
                elif .Field == "query-string" then
                  {
                    field: .Field,
                    values: (.QueryStringConfig.Values // []),
                    text: (
                      "query-string=" + (
                        (.QueryStringConfig.Values // [])
                        | map(
                            if (.Key // "") == "" then (.Value // "")
                            else (.Key + "=" + (.Value // ""))
                            end
                          )
                        | join("&")
                      )
                    )
                  }
                elif .Field == "source-ip" then
                  {
                    field: .Field,
                    values: (.SourceIpConfig.Values // []),
                    text: ("source-ip=" + ((.SourceIpConfig.Values // []) | join(",")))
                  }
                else
                  { field: (.Field // "unknown"), text: ((.Field // "unknown") + "=<unknown>") }
                end
              )
            ),
            actions: (
              ($r.Actions // []) | map(
                if .Type == "forward" then
                  {
                    type: .Type,
                    targetGroupArns: (
                      if .TargetGroupArn then
                        [.TargetGroupArn]
                      elif (.ForwardConfig.TargetGroups // null) then
                        (.ForwardConfig.TargetGroups | map(.TargetGroupArn))
                      else
                        []
                      end
                    ),
                    text: (
                      if .TargetGroupArn then
                        "forward:" + (.TargetGroupArn | split("/") | .[-1])
                      elif .ForwardConfig.TargetGroups then
                        "forward:" + (.ForwardConfig.TargetGroups | map(.TargetGroupArn | split("/") | .[-1]) | join(","))
                      else
                        "forward"
                      end
                    )
                  }
                elif .Type == "redirect" then
                  { type: .Type, text: "redirect" }
                elif .Type == "fixed-response" then
                  { type: .Type, text: "fixed-response" }
                elif .Type == "authenticate-cognito" then
                  { type: .Type, text: "auth-cognito" }
                elif .Type == "authenticate-oidc" then
                  { type: .Type, text: "auth-oidc" }
                else
                  { type: (.Type // "unknown"), text: (.Type // "unknown") }
                end
              )
            )
          }
        | if .name == "" then .name = ("(无Name标签)-" + (.ruleArn | split("/") | .[-1])) else . end
      )'
}

# 套用筛选条件
filter_structured_rules_json() {
  local structured="$1"

  echo "$structured" | jq \
    --arg ruleName "$FILTER_RULE_NAME" \
    --arg nameLike "$FILTER_NAME_LIKE" \
    --arg priority "$FILTER_PRIORITY" \
    --arg headerName "$FILTER_HEADER_NAME" '
    map(
      select(
        ($ruleName == "" or .name == $ruleName)
        and
        ($nameLike == "" or (.name | contains($nameLike)))
        and
        ($priority == "" or .priority == $priority)
        and
        (
          $headerName == ""
          or
          (
            [.conditions[]? | select(.field == "http-header") | (.httpHeaderName // "")]
            | any(. == $headerName)
          )
        )
      )
    )'
}

print_rules_table() {
  local structured="$1"

  printf "%-10s | %-24s | 条件 | 操作\n" "优先级" "名称"
  printf -- "========================================================================================================================\n"

  echo "$structured" | jq -c '.[]' | while IFS= read -r r; do
    local p n cond actions
    p="$(echo "$r" | jq -r '.priority')"
    n="$(echo "$r" | jq -r '.name')"
    cond="$(echo "$r" | jq -r '
      if (.conditions|length)==0 then "-"
      else (.conditions | map(.text) | join(" ; "))
      end
    ')"
    actions="$(echo "$r" | jq -r '
      if (.actions|length)==0 then "-"
      else (.actions | map(.text) | join(" | "))
      end
    ')"

    printf "%-10s | %-24s | %s | %s\n" "$p" "$n" "$cond" "$actions"
  done
}

print_rules_pretty() {
  local structured="$1"

  local count
  count="$(echo "$structured" | jq 'length')"
  if [[ "$count" -eq 0 ]]; then
    echo "未匹配到任何规则"
    return
  fi

  echo "$structured" | jq -c '.[]' | while IFS= read -r r; do
    local p n arn
    p="$(echo "$r" | jq -r '.priority')"
    n="$(echo "$r" | jq -r '.name')"
    arn="$(echo "$r" | jq -r '.ruleArn')"

    echo "--------------------------------------------------------------------------------"
    echo "优先级: $p"
    echo "名称: $n"
    echo "RuleArn: $arn"

    echo "条件:"
    local cond_count
    cond_count="$(echo "$r" | jq '.conditions | length')"
    if [[ "$cond_count" -eq 0 ]]; then
      echo "  - 无"
    else
      echo "$r" | jq -c '.conditions[]' | while IFS= read -r c; do
        local field
        field="$(echo "$c" | jq -r '.field')"
        case "$field" in
          http-header)
            local hn vcount
            hn="$(echo "$c" | jq -r '.httpHeaderName // ""')"
            vcount="$(echo "$c" | jq '.values | length')"
            echo "  - http-header(${hn}) [${vcount}]"
            echo "$c" | jq -r '.values[]?' | nl -w1 -s'] ' | sed 's/^/      [/'
            ;;
          host-header|path-pattern|http-request-method|source-ip)
            local text
            text="$(echo "$c" | jq -r '.text')"
            echo "  - $text"
            ;;
          query-string)
            local text
            text="$(echo "$c" | jq -r '.text')"
            echo "  - $text"
            ;;
          *)
            local text
            text="$(echo "$c" | jq -r '.text')"
            echo "  - $text"
            ;;
        esac
      done
    fi

    echo "操作:"
    local act_count
    act_count="$(echo "$r" | jq '.actions | length')"
    if [[ "$act_count" -eq 0 ]]; then
      echo "  - 无"
    else
      echo "$r" | jq -r '.actions[].text' | sed 's/^/  - /'
    fi
  done
  echo "--------------------------------------------------------------------------------"
}

main() {
  check_deps
  parse_args "$@"

  local rules_json names_json structured filtered
  rules_json="$(get_rules_json)"
  names_json="$(get_rule_names_json "$rules_json")"
  structured="$(build_structured_rules_json "$rules_json" "$names_json")"
  filtered="$(filter_structured_rules_json "$structured")"

  case "$OUTPUT_MODE" in
    json)
      echo "$filtered"
      ;;
    pretty)
      print_rules_pretty "$filtered"
      ;;
    table)
      print_rules_table "$filtered"
      ;;
    *)
      echo "错误：未知输出模式 $OUTPUT_MODE"
      exit 1
      ;;
  esac
}

main "$@"
