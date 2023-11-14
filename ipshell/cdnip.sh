#!/bin/bash
export LANG=en_US.UTF-8

source function.sh

cd /root/cfipopw/ && rm -rf informlog && bash cdnac.sh

#sed -i '/api.cloudflare.com/d' /etc/hosts

# 调用login_cloudflare方法测试登录Cloudflare
login_cloudflare

echo "当前工作模式只支持ipv4";

## 执行clouflare 测速功能
cloudflareSpeedTest

# 调用处理优选IP结果的方法
handle_optimized_ip_result

# 调用更新DNS记录的函数
update_dns_with_common_country_code

# 读取informlog文件的内容
informlog_content=$(cat informlog)

# 调用tgaction发送informlog文件的内容
tgaction "$informlog_content"

echo "切记：在软路由-计划任务选项中，加入优选IP自动执行时间的cron表达式"
echo "比如每天早上三点执行：0 3 * * * cd /root/cfipopw/ && bash cdnip.sh"
exit
