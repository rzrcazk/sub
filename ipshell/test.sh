#!/bin/bash
# main.sh

# 加载方法脚本
source function.sh

# tg 参数
message_text="这是测试消息"
telegramBotToken="5573048058:AAGGIA-EsLBWzHXOR2wIkgRGJOvXRyJN0u8"
telegramBotUserId="5374450210"
tgapi="tg.juanshen.eu.org"


# cloudflare
zone_id="eb7b800189c2f46998692a01cddeb1f5"
x_email="gyanzhuan051@gmail.com"
api_key="eabfd022902ba8b12a9f67d9ddbf1bd75ad87eabfd022902ba8b12a9f67d9ddbf1bd75ad87"
# 调用函数
# tgaction "$message_text" "$telegramBotToken" "$telegramBotUserId" "$tgapi"


# 调用login_cloudflare方法测试登录Cloudflare
#login_cloudflare "$zone_id" "$x_email" "$api_key"


# 调用选择客户端的方法
choose_client "$clien"