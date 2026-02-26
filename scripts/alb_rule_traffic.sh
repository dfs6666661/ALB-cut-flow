#!/usr/bin/env bash
set -euo pipefail

# ===== 在这里手工配置 region/profile（不配就走环境变量/默认配置）=====
REGION="${AWS_REGION:-us-east-1}"
PROFILE="${AWS_PROFILE:-}"

AWS_ARGS=(--region "$REGION")
[[ -n "$PROFILE" ]] && AWS_ARGS+=(--profile "$PROFILE")

need() { command -v "$1" >/dev/null 2>&1 || { echo "缺少依赖：$1"; exit 1; }; }
need aws
need jq

# ===== 配置清单 =====
CONFIG_JSON='
[
  {
    "ruleArn": "arn:aws:elasticloadbalancing:us-east-1:992382714390:listener-rule/app/mpaasgw/25907e5a3a778b9b/a4c63ea23ad0a4f7/eac7d9581d15c910",
    "prTgArn": "arn:aws:elasticloadbalancing:us-east-1:992382714390:targetgroup/mpaasgw-az1-prod-tg/88c970b4725d250d",
    "drTgArn": "arn:aws:elasticloadbalancing:us-east-1:992382714390:targetgroup/mpaas-az2-prod-tg/a2c7bf8df6165ee2",
    "allTgArn": "arn:aws:elasticloadbalancing:us-east-1:992382714390:targetgroup/mpaasgw-internet/55f5ba376371ad62"
  },
  {
    "ruleArn": "arn:aws:elasticloadbalancing:us-east-1:992382714390:listener-rule/app/supergw/403db1a4e68a06d4/ba5ebe138d4db640/317997a414638446",
    "prTgArn": "arn:aws:elasticloadbalancing:us-east-1:992382714390:targetgroup/supergw-az1-prod-tg/7b7ee60e756b1149",
    "drTgArn": "arn:aws:elasticloadbalancing:us-east-1:992382714390:targetgroup/supergw-az2-prod-tg/6366132f254706ab",
    "allTgArn": "arn:aws:elasticloadbalancing:us-east-1:992382714390:targetgroup/supergw-border-nlb/a49bcb0a9741c230"
  },

  {
    "ruleArn": "arn:aws:elasticloadbalancing:us-east-1:992382714390:listener-rule/app/backoffice-prod-internal-alb/a4343c78f8486445/b4b66591c4895234/570c5576291ec381",
    "prTgArn": "arn:aws:elasticloadbalancing:us-east-1:992382714390:targetgroup/backoffice-internet-az1-prod-tg/0716d38ec9f0dfa3",
    "drTgArn": "arn:aws:elasticloadbalancing:us-east-1:992382714390:targetgroup/backoffice-internet-az2-prod-tg/a722ea02c93359a4",
    "allTgArn": "arn:aws:elasticloadbalancing:us-east-1:992382714390:targetgroup/backoffice-internet-prod-tg/5dab24bd24ac7e5b"
  },
   {
    "ruleArn": "arn:aws:elasticloadbalancing:us-east-1:992382714390:listener-rule/app/dfp/3732ddb01148344e/22949eed57b099e7/1d1dce2e4752e1a3",
    "prTgArn": "arn:aws:elasticloadbalancing:us-east-1:992382714390:targetgroup/dfp-az1-prod-tg/becb1b831f6f0050",
    "drTgArn": "arn:aws:elasticloadbalancing:us-east-1:992382714390:targetgroup/dfp-az2-prod-tg/b9a5eb6cf3c95ed2",
    "allTgArn": "arn:aws:elasticloadbalancing:us-east-1:992382714390:targetgroup/dfp-prod-tg/9ef86a18fce6a267"
},

   {
    "ruleArn": "arn:aws:elasticloadbalancing:us-east-1:992382714390:listener-rule/app/apmarketingmng-internal/6311c84c2215d2c0/9edfa1a47e2d201a/420944d934ee1017",
    "prTgArn": "arn:aws:elasticloadbalancing:us-east-1:992382714390:targetgroup/apmarketingmng-az1/ca7064886c799b4e",
    "drTgArn": "arn:aws:elasticloadbalancing:us-east-1:992382714390:targetgroup/apmarketingmng-az2/6c8806727c4932bc",
    "allTgArn": "arn:aws:elasticloadbalancing:us-east-1:992382714390:targetgroup/apmarketingmng-internal-border/28df91a93f8997e4"
  },
   {
    "ruleArn": "arn:aws:elasticloadbalancing:us-east-1:992382714390:listener-rule/app/appaymentmng-internal/6ea9e98cac03900b/6291f68d5687051b/129625498df4518f",
    "prTgArn": "arn:aws:elasticloadbalancing:us-east-1:992382714390:targetgroup/appaymentmng-az1/5ee2c6c9412881e7",
    "drTgArn": "arn:aws:elasticloadbalancing:us-east-1:992382714390:targetgroup/appaymentmng-az2/c8205564a8aaf578",
    "allTgArn": "arn:aws:elasticloadbalancing:us-east-1:992382714390:targetgroup/appaymentmng-internal-border/1ce1a3e7b60e4b01"
  },
   {
    "ruleArn": "arn:aws:elasticloadbalancing:us-east-1:992382714390:listener-rule/app/buservice-internal/fb588129fb6da366/844930842747137f/f5cf3beec498dcd2",
    "prTgArn": "arn:aws:elasticloadbalancing:us-east-1:992382714390:targetgroup/buservice-az1/7aa9613c2729d2c5",
    "drTgArn": "arn:aws:elasticloadbalancing:us-east-1:992382714390:targetgroup/buservice-az2/766ba96b8de2bcbb",
    "allTgArn": "arn:aws:elasticloadbalancing:us-east-1:992382714390:targetgroup/buservice-internal-border/d5052f7c86cf7480"
  },
   {
    "ruleArn": "arn:aws:elasticloadbalancing:us-east-1:992382714390:listener-rule/app/cfmng-internal/d8ec55a0c8e675b8/abbb6a4c67f4772b/01c1b39abf0bed59",
    "prTgArn": "arn:aws:elasticloadbalancing:us-east-1:992382714390:targetgroup/cfmng-az1/b27dfdf4a3ed95bc",
    "drTgArn": "arn:aws:elasticloadbalancing:us-east-1:992382714390:targetgroup/cfmng-az2/045e0595983eb8b8",
    "allTgArn": "arn:aws:elasticloadbalancing:us-east-1:992382714390:targetgroup/cfmng-internal-border/83502f70aed2d7f2"
  },
   {
    "ruleArn": "arn:aws:elasticloadbalancing:us-east-1:992382714390:listener-rule/app/custmng-internal/2a2aedee97117811/8c957d89ac842f2c/82a9968f59d920cf",
    "prTgArn": "arn:aws:elasticloadbalancing:us-east-1:992382714390:targetgroup/custmng-az1/5b385a1aac4fa225",
    "drTgArn": "arn:aws:elasticloadbalancing:us-east-1:992382714390:targetgroup/custmng-az2/0853087749ebd7a8",
    "allTgArn": "arn:aws:elasticloadbalancing:us-east-1:992382714390:targetgroup/custmng-internal-border/0d7d961e03f156ba"
  },
   {
    "ruleArn": "arn:aws:elasticloadbalancing:us-east-1:992382714390:listener-rule/app/apasset-internal/093e15739b6d820c/e60b2974d199cb8a/7de04dab48f512e5",
    "prTgArn": "arn:aws:elasticloadbalancing:us-east-1:992382714390:targetgroup/apasset-az1/de92cab7e5af8637",
    "drTgArn": "arn:aws:elasticloadbalancing:us-east-1:992382714390:targetgroup/apasset-az2/eeb371912e440424",
    "allTgArn": "arn:aws:elasticloadbalancing:us-east-1:992382714390:targetgroup/apasset-internal-border/7a6bdf2917afa360"
  },
   {
    "ruleArn": "arn:aws:elasticloadbalancing:us-east-1:992382714390:listener-rule/app/fluxworks-internal/9b428a7cbf04fb79/589b46e562af5b66/f2d44b633ac22311",
    "prTgArn": "arn:aws:elasticloadbalancing:us-east-1:992382714390:targetgroup/fluxworks-az1/4ee16da1772921e3",
    "drTgArn": "arn:aws:elasticloadbalancing:us-east-1:992382714390:targetgroup/fluxworks-az2/39b11934be2af124",
    "allTgArn": "arn:aws:elasticloadbalancing:us-east-1:992382714390:targetgroup/fluxworks-internal-border/bf9f90e87070d9db"
  },
   {
    "ruleArn": "arn:aws:elasticloadbalancing:us-east-1:992382714390:listener-rule/app/process-internal/4b4c5ff15c92c239/2910bb3ad4dd6866/45994b2161bfe283",
    "prTgArn": "arn:aws:elasticloadbalancing:us-east-1:992382714390:targetgroup/process-az1/00ef3f885c3b15f7",
    "drTgArn": "arn:aws:elasticloadbalancing:us-east-1:992382714390:targetgroup/process-az2/d7c407aae474a833",
    "allTgArn": "arn:aws:elasticloadbalancing:us-east-1:992382714390:targetgroup/process-internal-border/3bb1defc80798fdf"
  },
   {
    "ruleArn": "arn:aws:elasticloadbalancing:us-east-1:992382714390:listener-rule/app/prodmng-internal/01349aff0ef6ca13/d969ff17150bb36b/9580c39699306407",
    "prTgArn": "arn:aws:elasticloadbalancing:us-east-1:992382714390:targetgroup/prodmng-az1/e50f772c7691679f",
    "drTgArn": "arn:aws:elasticloadbalancing:us-east-1:992382714390:targetgroup/prodmng-az2/ade3f6294b541f5b",
    "allTgArn": "arn:aws:elasticloadbalancing:us-east-1:992382714390:targetgroup/prodmng-internal-border/77abf3ce6fe4236b"
  },
   {
    "ruleArn": "arn:aws:elasticloadbalancing:us-east-1:992382714390:listener-rule/app/riskengineportal-internal/bc124d0f4e00c57f/efebe305ac0f19e7/2ea68ab1fdc7ca4b",
    "prTgArn": "arn:aws:elasticloadbalancing:us-east-1:992382714390:targetgroup/riskengineportal-az1/18218b157adbb195",
    "drTgArn": "arn:aws:elasticloadbalancing:us-east-1:992382714390:targetgroup/riskengineportal-az2/63680c5879ddfad6",
    "allTgArn": "arn:aws:elasticloadbalancing:us-east-1:992382714390:targetgroup/riskengineportal-internal-border/3086df8433008ee6"
  },
    {
    "ruleArn": "arn:aws:elasticloadbalancing:us-east-1:992382714390:listener-rule/app/rds-medusa-alb/4ad8cfe4770dec87/76fb5ebfca450ef3/e7f2fc4a6c2e5ba8",
    "prTgArn": "arn:aws:elasticloadbalancing:us-east-1:992382714390:targetgroup/rds-meudsa-az1-tg/864a3e2366eeee2d",
    "drTgArn": "arn:aws:elasticloadbalancing:us-east-1:992382714390:targetgroup/rds-medusa-az2-tg/9bb517bf422ea45a",
    "allTgArn": "arn:aws:elasticloadbalancing:us-east-1:992382714390:targetgroup/rds-medusa-border-tg/2772fbd9cdfe395a"
  },
    {
    "ruleArn": "arn:aws:elasticloadbalancing:us-east-1:992382714390:listener-rule/app/supergw-border/f6d629fe3a660f35/7545c7b9a4bff07c/af1030532195e8c1",
    "prTgArn": "arn:aws:elasticloadbalancing:us-east-1:992382714390:targetgroup/supergw-az1-prod-tg-border/06a5a5c36ce0a63c",
    "drTgArn": "arn:aws:elasticloadbalancing:us-east-1:992382714390:targetgroup/supergw-az2-prod-tg-border/fc20c9e52d261037",
    "allTgArn": "arn:aws:elasticloadbalancing:us-east-1:992382714390:targetgroup/supergw-border-nlb-border/69127cfddf949245"
 },
    {
    "ruleArn": "arn:aws:elasticloadbalancing:us-east-1:992382714390:listener-rule/app/merchant-portal-prod/52221fdcd77b33be/6d60ed240187e654/61a53449b2aa4946",
    "prTgArn": "arn:aws:elasticloadbalancing:us-east-1:992382714390:targetgroup/merchant-nginx-prod-az1/2e7388373e383a48",
    "drTgArn": "arn:aws:elasticloadbalancing:us-east-1:992382714390:targetgroup/merchant-nginx-prod-az2/c09bf3b807fe96a1",
    "allTgArn": "arn:aws:elasticloadbalancing:us-east-1:992382714390:targetgroup/prod-merchant-nginx/a2762679ecf8f12c"
 }
]
'

# ===== 工具函数 =====

# 从 ruleArn 解析出 ALB 名称：...:listener-rule/app/<lb-name>/<lb-id>/<listener-id>/<rule-id>
alb_name_from_rule_arn() {
  local ruleArn="$1"
  # 取 "listener-rule/app/<name>/..." 里的 <name>
  echo "$ruleArn" | sed -n 's#.*:listener-rule/app/\([^/]\+\)/.*#\1#p'
}

# 权重转百分比（整数）
pct() {
  local part="$1" total="$2"
  if [[ "$total" -le 0 ]]; then echo "0"; return; fi
  awk -v p="$part" -v t="$total" 'BEGIN{printf("%d", (p*100)/t)}'
}

# 在某条 rule 的 forward TG 列表里，找到指定 TG ARN 的权重
# 若 TG 不在该规则 forward 列表里，返回 0
weight_of_tg() {
  local rules_json="$1"
  local tg_arn="$2"
  echo "$rules_json" | jq -r --arg tg "$tg_arn" '
    [
      .Rules[]
      | .Actions[]?
      | select(.Type=="forward")
      | .ForwardConfig.TargetGroups[]?
      | select(.TargetGroupArn==$tg)
      | (.Weight // 1)
    ] | add // 0
  '
}

# 计算该规则 forward 列表里总权重（用于算比例）
total_forward_weight() {
  local rules_json="$1"
  echo "$rules_json" | jq -r '
    [
      .Rules[]
      | .Actions[]?
      | select(.Type=="forward")
      | .ForwardConfig.TargetGroups[]?
      | (.Weight // 1)
    ] | add // 0
  '
}

# ===== 主逻辑 =====

printf "%-28s\t%10s\t%10s\t%12s\n" "ALB名称" "AZ1流量占比" "AZ2流量占比" "双AZ流量占比"

# 遍历配置
echo "$CONFIG_JSON" | jq -c '.[]' | while read -r item; do
  ruleArn="$(echo "$item" | jq -r '.ruleArn')"
  prTgArn="$(echo "$item" | jq -r '.prTgArn')"
  drTgArn="$(echo "$item" | jq -r '.drTgArn')"
  allTgArn="$(echo "$item" | jq -r '.allTgArn')"

  albName="$(alb_name_from_rule_arn "$ruleArn")"
  [[ -z "$albName" ]] && albName="(unknown)"

  # 拉取规则详情
  # describe-rules 支持一次查多条，这里按条查，足够清晰；
  rules_json="$(aws "${AWS_ARGS[@]}" elbv2 describe-rules --rule-arns "$ruleArn" 2>/dev/null || true)"

  if [[ -z "$rules_json" || "$rules_json" == "null" ]]; then
    printf "%-28s\t%10s\t%10s\t%12s\n" "$albName" "ERR" "ERR" "ERR"
    continue
  fi

  total_w="$(total_forward_weight "$rules_json")"
  pr_w="$(weight_of_tg "$rules_json" "$prTgArn")"
  dr_w="$(weight_of_tg "$rules_json" "$drTgArn")"
  all_w="$(weight_of_tg "$rules_json" "$allTgArn")"

  # 百分比用 total_forward_weight 做分母
  pr_p="$(pct "$pr_w" "$total_w")"
  dr_p="$(pct "$dr_w" "$total_w")"
  all_p="$(pct "$all_w" "$total_w")"

  printf "%-28s\t%10s\t%10s\t%12s\n" "$albName" "$pr_p" "$dr_p" "$all_p"
done

