#!/bin/bash
# 加载配置文件
source config.sh

## tg推送
tgaction(){
    local message_text="$1" # 使用局部变量接收传递的参数
    echo "调用 tgaction，消息内容: '$message_text'" # 打印调用细节

    if [[ -z ${telegramBotToken} ]]; then
        echo "未配置TG推送"
    else
        local MODE='HTML'
        local URL="https://${tgapi}/bot${telegramBotToken}/sendMessage"
        echo "发送请求到: $URL" # 打印请求的 URL

        local res=$(timeout 20s curl -s -X POST "$URL" -d chat_id="${telegramBotUserId}" -d parse_mode="${MODE}" -d text="${message_text}")
        echo "响应结果: $res" # 打印响应结果

        if [ $? -eq 124 ]; then
            echo 'TG_api请求超时,请检查网络是否重启完成并是否能够访问TG'
        else
            local resSuccess=$(echo "$res" | jq -r ".ok")
            if [[ $resSuccess = "true" ]]; then
                echo "TG推送成功"
            else
                echo "TG推送失败，请检查TG机器人token和ID"
            fi
        fi
    fi
}


login_cloudflare() {
    for ((i=1; i<=$max_retries; i++)); do
        local curl_cmd="curl -sm10 -X GET 'https://api.cloudflare.com/client/v4/zones/${zone_id}' -H 'X-Auth-Email:$x_email' -H 'X-Auth-Key:$api_key' -H 'Content-Type:application/json'"
        echo "执行命令: $curl_cmd" # 打印完整的 curl 命令

        local res=$(eval $curl_cmd)
        resSuccess=$(echo "$res" | jq -r ".success")
        if [[ $resSuccess == "true" ]]; then
            echo "Cloudflare账号登陆成功!"
            break
        elif [ $i -eq $max_retries ]; then
            echo "尝试5次登陆CF失败，检查CF邮箱、区域ID、API Key"
            local pushmessage="尝试5次登陆CF失败，检查CF邮箱、区域ID、API Key"
            tgaction "$pushmessage"
            exit
        else
            echo "Cloudflare账号登陆失败，尝试重连 ($i/$max_retries)..."
            sleep 2
        fi
    done
}






# 新添加的处理优选IP结果的方法
handle_optimized_ip_result() {
    # 检查result.csv文件是否存在
    if [ -f "/root/cfipopw/result.csv" ]; then
        # 读取第二行并删除空白字符
        second_line=$(sed -n '2p' /root/cfipopw/result.csv | tr -d '[:space:]')

        # 如果第二行为空，则认为优选IP失败
        if [ -z "$second_line" ]; then
            echo "优选IP失败，请尝试更换端口或者重新执行一次" && sleep 3
            local pushmessage="优选IP失败，请尝试更换端口或者重新执行一次"
            tgaction "$pushmessage" # 调用通知方法
            exit
        fi

        # 获取CFST_DN环境变量的值，并进行后续操作
        local num=$CFST_DN
        local new_num=$((num + 1))

        # 如果第二行的第六列（延迟值）为0.00，则更新result.csv文件
        if [ $(awk -F, 'NR==2 {print $6}' /root/cfipopw/result.csv) == 0.00 ]; then
            awk -F, "NR<=$new_num" /root/cfipopw/result.csv > /root/cfipopw/new_result.csv
            mv /root/cfipopw/new_result.csv /root/cfipopw/result.csv
        fi

        # 如果result.csv文件中有超过11行数据，则只保留前11行数据
        if [[ $(awk -F ',' 'NR==12 {print $1}' /root/cfipopw/result.csv) ]]; then
            awk -F ',' 'NR>1 && NR<=11 {print $1}' /root/cfipopw/result.csv > /root/cfipopw/new_result.csv
            mv /root/cfipopw/new_result.csv /root/cfipopw/result.csv
        fi

        # 清理/etc/hosts文件中关于Cloudflare API的条目
        sed -i '/api.cloudflare.com/d' /etc/hosts
    else
        # 如果result.csv文件不存在，认为优选IP中断
        echo "优选IP中断，未生成result.csv文件，请尝试更换端口或者重新执行一次" && sleep 3
        local pushmessage="优选IP中断，未生成result.csv文件，请尝试更换端口或者重新执行一次"
        tgaction "$pushmessage" # 调用通知方法
        exit
    fi
    echo "测速完毕"
}




# 函数：获取给定IP的国家代码

get_country_code_by_ip() {
    local ip=$1
    local curl_cmd="curl -s --max-time 10 'http://ip-api.com/json/${ip}'"
    echo "执行命令: $curl_cmd" # 打印完整的 curl 命令

    local response=$(eval $curl_cmd)
    local country_code=$(echo "$response" | jq -r '.countryCode')

    if [ "$country_code" == "null" ] || [ -z "$country_code" ]; then
        echo "Error: 无法获取有效的国家代码"
        return 1
    fi

    echo $country_code
    return 0
}



# 添加DNS记录的函数
add_dns_record() {
    local ip=$1
    local record_name=$2
    local data="{\"type\":\"A\",\"name\":\"$record_name\",\"content\":\"$ip\",\"ttl\":1,\"proxied\":false}"
    local curl_cmd="curl -s -X POST 'https://api.cloudflare.com/client/v4/zones/$zone_id/dns_records' -H 'X-Auth-Email: $x_email' -H 'X-Auth-Key: $api_key' -H 'Content-Type: application/json' --data '$data'"

    echo "执行命令: $curl_cmd" # 打印完整的 curl 命令

    local response=$(eval $curl_cmd)
    if [[ $(echo "$response" | jq -r '.success') == "true" ]]; then
        echo "IP地址 $ip 成功解析到 ${record_name}.${domain}" >> informlog
    else
        echo "导入IP地址 $ip 失败" >> informlog
    fi
}



# 删除所有与域名关联的DNS记录的函数
delete_all_dns_records() {
    local zone_id=$1
    local record_name=$2

    # 获取所有DNS记录的命令
    local get_cmd="curl -s --max-time 5 -X GET 'https://api.cloudflare.com/client/v4/zones/$zone_id/dns_records?name=$record_name' -H 'X-Auth-Email: $x_email' -H 'X-Auth-Key: $api_key' -H 'Content-Type: application/json'"
    echo "执行命令: $get_cmd" # 打印完整的获取命令

    local records=$(eval $get_cmd)
    if [ $? -ne 0 ] || [ -z "$records" ]; then
        echo "Error: 获取DNS记录失败"
        return 1
    fi

    # 遍历并删除每个DNS记录
    echo "$records" | jq -c '.result[] | .id' | while read -r id; do
        local delete_cmd="curl -s --max-time 5 -X DELETE 'https://api.cloudflare.com/client/v4/zones/$zone_id/dns_records/$id' -H 'X-Auth-Email: $x_email' -H 'X-Auth-Key: $api_key' -H 'Content-Type: application/json'"
        echo "执行命令: $delete_cmd" # 打印完整的删除命令

        local delete_response=$(eval $delete_cmd)
        if [ $? -ne 0 ]; then
            echo "Error: 删除DNS记录 $id 失败"
        fi
    done
}


# 函数：更新DNS记录
update_dns_with_common_country_code() {
    local csv_file="/root/cfipopw/result.csv" # CSV文件路径
    local informlog_file='informlog'
    declare -A country_count=()
    declare -A ip_country=()
    declare -A unique_ips
    local found_country_code=false

    # 读取IP地址，并获取每个IP的国家代码
    while IFS=, read -r ip rest; do
        if [[ ! ${unique_ips[$ip]} ]]; then
            unique_ips[$ip]=1
            if [[ $ip =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ || $ip =~ ^[0-9a-fA-F:]+$ ]]; then # 检查IP格式
                country_code=$(get_country_code_by_ip "$ip")
                if [ $? -ne 0 ]; then
                    echo "无法获取国家代码，将IP $ip 视为默认国家的一部分" >> "$informlog_file"
                    country_code="DEFAULT"
                else
                    found_country_code=true
                fi
                ((country_count[$country_code]++))
                ip_country[$ip]=$country_code
            fi
        fi
    done < <(tail -n +2 $csv_file) # 跳过CSV的标题行

    # 找出出现最多次的country_code或使用默认值
    max_count=0
    common_country_code=""
    if [ "$found_country_code" = true ]; then
        for country_code in "${!country_count[@]}"; do
            if [[ "${country_count[$country_code]}" -gt "$max_count" ]]; then
                max_count=${country_count[$country_code]}
                common_country_code=$country_code
            fi
        done
    else
        common_country_code="DEFAULT"
    fi

    echo '删除DNS记录开始'
    # 删除现有DNS记录
    delete_all_dns_records "$zone_id" "$x_email" "$api_key" "$subdomain.$domain"
    echo '删除DNS记录结束'

    # 为最常见的country_code的IP地址创建DNS记录
    for ip in "${!ip_country[@]}"; do
        echo "Adding DNS record for IP $ip with country code $common_country_code"
        add_dns_record "$ip" "$subdomain.$domain" "$zone_id" "$x_email" "$api_key" "A"
    done

    # 确保informlog文件至少有一些内容
    if [ ! -s "$informlog_file" ]; then
        echo "无记录" >> "$informlog_file"
    fi
}



## 测速
cloudflareSpeedTest(){
  echo "模拟测速成功"
  #./cfst -tp $point $CFST_URL_R -t $CFST_T -n $CFST_N -dn $CFST_DN -p $CFST_DN -tl $CFST_TL -tll $CFST_TLL -sl $CFST_SL $CFST_SPD -dt 8
}



