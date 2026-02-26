curl -v -XPOST '100.65.6.231:8341/openapi/message/servertag' -d 'old_server_tag=zlqbb-mq-msgbroker-0&new_server_tag=zlqba-mq-msgbroker-0'
curl -v -XPOST '100.65.6.231:8341/openapi/message/servertag' -d 'old_server_tag=zlqbb-mq-msgbroker-1&new_server_tag=zlqba-mq-msgbroker-1'
curl -X POST http://100.65.7.10:8080/openapi/ts/config/delete -H 'Content-Type:application/x-www-form-urlencoded' --data-urlencode 'instanceId=8OYJNOVRAZRC' --data-urlencode 'configKey=switchZone'

curl -X POST http://100.65.7.10:8080/openapi/ts/config/add -H 'Content-Type:application/x-www-form-urlencoded' --data-urlencode 'instanceId=8OYJNOVRAZRC' --data-urlencode 'configKey=switchZone' --data-urlencode 'configValue={"GZ00B":"GZ00A"}'

