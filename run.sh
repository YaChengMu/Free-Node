#!/bin/sh
#########################################################
# 节点订阅自动获取脚本 - 并行模板版本
# 功能：自动查找可用的节点URL并生成订阅
# 特点：并行检测、超时控制、多模板支持
#########################################################

# ===== 日期处理函数 =====

# 获取当前日期（多种格式）
get_current_date() {
    # 完整日期（年月日）
    currentdate=$(date +%Y%m%d)
    currentyear=$(date +%Y)
    # 包含前导零的月份和日期
    currentmonth_padded=$(date +%m)
    currentday_padded=$(date +%d)
    # 不包含前导零的月份和日期
    currentmonth=$(date +%-m 2>/dev/null || date +%m | sed 's/^0*//')
    currentday=$(date +%-d 2>/dev/null || date +%d | sed 's/^0*//')
}

# 计算前N天的日期函数
calculate_previous_date() {
    days_to_subtract=$1
    # 在POSIX shell中使用不同的日期计算方法
    target_date=$(date -d "$currentyear-$currentmonth_padded-$currentday_padded -$days_to_subtract days" +"%Y %m %d %m %d" 2>/dev/null || echo "$currentyear $currentmonth_padded $currentday_padded $currentmonth $currentday")
    echo $target_date
}

# ===== URL处理函数 =====

# URL解码函数
urldecode() {
    url_encoded="$1"
    # 替换+为空格
    url_encoded=$(echo "$url_encoded" | sed 's/+/ /g')
    # 解码%编码的字符
    printf '%b' "$(echo "$url_encoded" | sed 's/%/\\\\x/g')"
}

# URL编码函数（不依赖外部工具）
urlencode() {
    string="$1"
    strlen=$(echo "$string" | wc -c)
    strlen=$((strlen - 1))  # 减去换行符的长度
    
    encoded=""
    pos=0
    
    while [ $pos -lt $strlen ]; do
        pos=$((pos + 1))
        c=$(echo "$string" | cut -c$pos-$pos)
        case "$c" in
            [-_.~a-zA-Z0-9]) # 这些字符不需要编码
                encoded="$encoded$c"
                ;;
            *)
                # 将字符转换为十六进制
                hex=$(printf '%02x' "'$c" 2>/dev/null || printf '%%02x' "'$c")
                encoded="$encoded%$hex"
                ;;
        esac
    done
    echo "$encoded"
}

# 检查URL可用性
check_url_availability() {
    url="$1"
    # 使用curl检查URL是否可访问
    # -s: 静默模式，不显示进度
    # -L: 跟随重定向
    # -I: 只获取头信息
    # --connect-timeout 10: 连接超时10秒
    # --max-time 20: 总超时20秒
    status_code=$(curl -s -L -I --connect-timeout 10 --max-time 20 -o /dev/null -w '%{http_code}' "$url")
    
    # 检查状态码是否为200或30x（表示成功或重定向）
    case "$status_code" in
        200|30[0-9])
            return 0  # URL可用
            ;;
        *)
            return 1  # URL不可用
            ;;
    esac
}

# 检查单个模板的URL可用性
check_template_urls() {
    template_key="$1"
    template="$2"
    param1_type="$3"
    param2_type="$4"
    param3_type="$5"
    max_days_to_check=7  # 最多检查7天
    
    # 初始化日期变量
    year=$currentyear
    month_padded=$currentmonth_padded
    date_padded=$currentday_padded
    month_no_zero=$currentmonth
    date_no_zero=$currentday
    date_full="${year}${month_padded}$(printf "%02d" $date_padded)"
    
    echo "模板[$template_key]: 开始检查URL可用性"
    
    # 检查最近几天的URL (从当天开始)
    i=0
    while [ $i -lt $max_days_to_check ]; do
        # 计算日期 (当天及之前几天)
        if [ $i -gt 0 ]; then
            date_info=$(calculate_previous_date $i)
            year=$(echo $date_info | cut -d' ' -f1)
            month_padded=$(echo $date_info | cut -d' ' -f2)
            date_padded=$(echo $date_info | cut -d' ' -f3)
            month_no_zero=$(echo $date_info | cut -d' ' -f4)
            date_no_zero=$(echo $date_info | cut -d' ' -f5)
            date_full="${year}${month_padded}$(printf "%02d" $date_padded)"
        fi
        
        # 根据参数类型选择对应的值
        check_param1=$year  # 年份总是相同格式
        
        # 处理月份参数
        case $param2_type in
            "month") check_param2=$month_padded ;;
            "month_no_zero") check_param2=$month_no_zero ;;
            "month_padded") check_param2=$month_padded ;;
            *) check_param2=$month_no_zero ;;  # 默认使用无前导零
        esac
        
        # 处理日期参数
        case $param3_type in
            "date") check_param3=$date_padded ;;
            "date_no_zero") check_param3=$date_no_zero ;;
            "date_padded") check_param3=$date_padded ;;
            "date_full") check_param3=$date_full ;;
            *) check_param3=$date_padded ;;  # 默认使用带前导零的日期
        esac
        
        # 使用printf格式化URL
        check_url=$(printf "$template" "$check_param1" "$check_param2" "$check_param3")
        
        echo "检查: $check_url"
        if check_url_availability "$check_url"; then
            echo "可用: $check_url"
            echo "$check_url"
            break
        else
            echo "不可用: $check_url"
        fi
        
        # 每检查5天打印一次进度
        remainder=$(( (i+1) % 5 ))
        if [ $remainder -eq 0 ]; then
            echo "已检查 $((i+1)) 天，继续搜索..."
        fi
        
        i=$((i + 1))
    done
}

# ===== 主程序 =====

# 初始化日期变量
get_current_date

# 定义URL模板结构体
# 格式: "URL模板|年份参数类型|月份参数类型|日期参数类型"
url_template_1="https://a.nodeshare.xyz/uploads/%s/%s/%s.yaml|year|month_no_zero|date_full"
url_template_2="https://nodefree.githubrowcontent.com/%s/%s/%s.yaml|year|month_padded|date_full"
url_template_3="https://free.datiya.com/uploads/%s-clash.yaml|date_full"
url_template_4="https://fastly.jsdelivr.net/gh/ripaojiedian/freenode@main/clash"
url_template_5="https://www.xrayvip.com/free.yaml"
url_template_6="https://ghproxy.net/https://raw.githubusercontent.com/anaer/Sub/main/clash.yaml"
url_template_7="https://ghproxy.net/https://raw.githubusercontent.com/Pawdroid/Free-servers/main/sub"
url_template_8="https://fastly.jsdelivr.net/gh/zhangkaiitugithub/passcro@main/speednodes.yaml"
url_template_9="https://raw.githubusercontent.com/ermaozi/get_subscribe/main/subscribe/clash.yml"
url_template_10="https://raw.githubusercontent.com/go4sharing/sub/main/sub.yaml"
url_template_11="https://raw.githubusercontent.com/Jsnzkpg/Jsnzkpg/Jsnzkpg/Jsnzkpg"
url_template_12="https://raw.githubusercontent.com/ermaozi01/free_clash_vpn/main/subscribe/clash.yml"

# 用于存储每个模板找到的可用URL
template_valid_urls_1=""
template_valid_urls_2=""
template_valid_urls_3=""
template_valid_urls_4=""
template_valid_urls_5=""
template_valid_urls_6=""
template_valid_urls_7=""
template_valid_urls_8=""
template_valid_urls_9=""
template_valid_urls_10=""
template_valid_urls_11=""
template_valid_urls_12=""

echo "========== 开始查找可用节点 =========="

# 创建临时文件存储并行任务结果
temp_file=$(mktemp)

# 并行检查所有模板
i=1
while [ $i -le 12 ]; do
    # 解析模板和参数
    eval "template_info=\$url_template_$i"
    template=$(echo "$template_info" | cut -d'|' -f1)
    param1_type=$(echo "$template_info" | cut -d'|' -f2)
    param2_type=$(echo "$template_info" | cut -d'|' -f3)
    param3_type=$(echo "$template_info" | cut -d'|' -f4)
    
    # 后台运行检查，结果写入临时文件
    (
        result=$(check_template_urls "$i" "$template" "$param1_type" "$param2_type" "$param3_type")
        if [ -n "$result" ]; then
            case "$result" in
                *"开始检查URL可用性"*)
                    # 不包含这个字符串，说明是有效的URL
                    echo "${i}|${result}" >> "$temp_file"
                    echo "使用模板[$i]: $result"
                    ;;
                *)
                    # 包含这个字符串，说明没有找到有效的URL
                    echo "$i|未找到可用URL" >> "$temp_file"
                    ;;
            esac
        else
            echo "$i|未找到可用URL" >> "$temp_file"
        fi
    ) &
    
    i=$((i + 1))
done

# 等待所有后台进程完成
wait

# 从临时文件加载结果
while IFS="|" read -r template_key result; do
    if [ "$result" != "未找到可用URL" ]; then
        eval "template_valid_urls_${template_key}=\"$result\""
    fi
done < "$temp_file"
rm -f "$temp_file"

echo "========== URL查找完成 =========="

# 统计找到的可用URL数量
found_count=0
i=1
while [ $i -le 12 ]; do
    eval "url_value=\$template_valid_urls_${i}"
    if [ -n "$url_value" ]; then
        found_count=$((found_count + 1))
    fi
    i=$((i + 1))
done

# 如果所有模板都未找到可用URL，才使用默认URL
if [ $found_count -eq 0 ]; then
    echo "警告: 所有模板均未找到可用URL，使用默认URL"
    i=1
    while [ $i -le 12 ]; do
        eval "template_info=\$url_template_$i"
        template=$(echo "$template_info" | cut -d'|' -f1)
        param1_type=$(echo "$template_info" | cut -d'|' -f2)
        param2_type=$(echo "$template_info" | cut -d'|' -f3)
        param3_type=$(echo "$template_info" | cut -d'|' -f4)
        
        # 使用当天日期生成默认URL
        date_full_default="${currentyear}${currentmonth_padded}$(printf "%02d" $currentday_padded)"
        
        # 根据模板参数数量和类型生成默认URL
        case $i in
            1)
                # 模板1: https://a.nodeshare.xyz/uploads/%s/%s/%s.yaml|year|month_no_zero|date_full
                eval "template_valid_urls_${i}=\"$(printf "$template" "$currentyear" "$currentmonth" "$date_full_default")\""
                ;;
            2)
                # 模板2: https://nodefree.githubrowcontent.com/%s/%s/%s.yaml|year|month_padded|date_full
                eval "template_valid_urls_${i}=\"$(printf "$template" "$currentyear" "$currentmonth_padded" "$date_full_default")\""
                ;;
            3)
                # 模板3: https://free.datiya.com/uploads/%s-clash.yaml|date_full
                eval "template_valid_urls_${i}=\"$(printf "$template" "$date_full_default")\""
                ;;
            *)
                # 处理其他模板 - 对于只有一个参数的模板（如模板4）
                if [ -z "$param2_type" ] && [ -z "$param3_type" ]; then
                    # 只有一个参数的模板，尝试用日期参数
                    eval "template_valid_urls_${i}=\"$(printf "$template" "$date_full_default")\""
                elif [ -n "$param1_type" ] && [ -n "$param2_type" ] && [ -n "$param3_type" ]; then
                    # 三个参数的模板
                    # 处理年份参数
                    case $param1_type in
                        "year") param1_val="$currentyear" ;;
                        *) param1_val="$currentyear" ;;
                    esac
                    
                    # 处理月份参数
                    case $param2_type in
                        "month") param2_val="$currentmonth_padded" ;;
                        "month_no_zero") param2_val="$currentmonth" ;;
                        "month_padded") param2_val="$currentmonth_padded" ;;
                        *) param2_val="$currentmonth" ;;
                    esac
                    
                    # 处理日期参数
                    case $param3_type in
                        "date") param3_val="$currentday_padded" ;;
                        "date_no_zero") param3_val="$currentday" ;;
                        "date_padded") param3_val="$currentday_padded" ;;
                        "date_full") param3_val="$date_full_default" ;;
                        *) param3_val="$date_full_default" ;;
                    esac
                    
                    eval "template_valid_urls_${i}=\"$(printf "$template" "$param1_val" "$param2_val" "$param3_val")\""
                elif [ -n "$param1_type" ] && [ -n "$param2_type" ] && [ -z "$param3_type" ]; then
                    # 两个参数的模板
                    # 处理第一个参数
                    case $param1_type in
                        "year") param1_val="$currentyear" ;;
                        *) param1_val="$currentyear" ;;
                    esac
                    
                    # 处理第二个参数
                    case $param2_type in
                        "month") param2_val="$currentmonth_padded" ;;
                        "month_no_zero") param2_val="$currentmonth" ;;
                        "month_padded") param2_val="$currentmonth_padded" ;;
                        "date_full") param2_val="$date_full_default" ;;
                        *) param2_val="$date_full_default" ;;
                    esac
                    
                    eval "template_valid_urls_${i}=\"$(printf "$template" "$param1_val" "$param2_val")\""
                fi
                ;;
        esac
        
        i=$((i + 1))
    done
else
    # 显示最终使用的URL
    i=1
    while [ $i -le 12 ]; do
        eval "url_value=\$template_valid_urls_${i}"
        if [ -n "$url_value" ]; then
            echo "使用模板[$i]: $url_value"
        fi
        i=$((i + 1))
    done
fi

# 收集所有有效的URL到一个数组
valid_urls=""
i=1
while [ $i -le 12 ]; do
    eval "url_value=\$template_valid_urls_${i}"
    if [ -n "$url_value" ]; then
        if [ -z "$valid_urls" ]; then
            valid_urls="$url_value"
        else
            valid_urls="$valid_urls|$url_value"
        fi
    fi
    i=$((i + 1))
done

# 使用管道符号(|)连接所有有效URL
combined_urls="$valid_urls"
echo "合并URL: $combined_urls"

# 对combined_urls进行URL编码
encoded_combined_urls=$(urlencode "$combined_urls")
echo "编码后URL: $encoded_combined_urls"

# 构建订阅链接
echo "========== 生成订阅链接 =========="
subscribeclash="https://api-suc.0z.gs/sub?target=clash&url=$encoded_combined_urls&insert=false&config=https%3A%2F%2Fraw.githubusercontent.com%2Fzsokami%2FACL4SSR%2Frefs%2Fheads%2Fmain%2FACL4SSR_Online_Full_Mannix_No_DNS_Leak.ini&filename=GitHub-GetNode&emoji=true&sort=true&udp=true"
subscribeV2ray="https://api-suc.0z.gs/sub?target=v2ray&url=$encoded_combined_urls&insert=false&config=https%3A%2F%2Fraw.githubusercontent.com%2Fzsokami%2FACL4SSR%2Frefs%2Fheads%2Fmain%2FACL4SSR_Online_Full_Mannix_No_DNS_Leak.ini&filename=GitHub-GetNode&emoji=true&sort=true&udp=true"

# 打印完整的订阅链接参数
echo "========== 订阅链接详情 =========="
echo "Clash订阅链接:"
echo "$subscribeclash" | fold -w 80

# 解析并打印订阅链接的各个参数
echo ""
echo "订阅链接参数解析:"
echo "- 目标格式: clash"
echo "- 源URL列表: "
i=1
while [ $i -le 12 ]; do
    eval "url_value=\$template_valid_urls_${i}"
    if [ -n "$url_value" ]; then
        echo "  * $url_value"
    fi
    i=$((i + 1))
done

# 解码配置URL
config_encoded="https%3A%2F%2Fraw.githubusercontent.com%2FNZESupB%2FProfile%2Fmain%2Foutpref%2Fpypref%2Fpyfull.ini"
config_decoded=$(urldecode "$config_encoded")
echo "- 配置文件: $config_decoded"

echo "- 文件名: GitHub-GetNode"
echo "- 其他参数:"
echo "  * emoji: true (添加Emoji图标)"
echo "  * sort: true (节点排序)"
echo "  * udp: true (启用UDP转发)"

# 保存订阅链接到文件
echo "$subscribeclash" > ./clash_subscribe_url.txt
echo "Clash订阅链接已保存到 clash_subscribe_url.txt"
echo ""

# 删除旧文件
if [ -f "./clash.yaml" ]; then
    rm -f ./clash.yaml
    echo "已删除旧的clash.yaml文件"
fi
if [ -f "./v2ray.txt" ]; then
    rm -f ./v2ray.txt
    echo "已删除旧的v2ray.txt文件"
fi

# 下载订阅
echo "========== 下载订阅文件 =========="
echo "下载Clash配置..."
if curl -s "$subscribeclash" -o ./clash.yaml; then
    echo "Clash配置下载成功"
else
    echo "Clash配置下载失败"
fi

echo "下载V2Ray配置..."
if curl -s "$subscribeV2ray" -o ./v2ray.txt; then
    echo "V2Ray配置下载成功"
else
    echo "V2Ray配置下载失败"
fi

echo "========== 任务完成 =========="
echo "生成的文件:"
echo "1. clash.yaml - Clash配置文件"
echo "2. v2ray.txt - V2Ray配置文件"
echo "3. clash_subscribe_url.txt - Clash订阅链接"
echo ""
echo "可以使用以下命令查看完整的订阅链接:"
echo "cat ./clash_subscribe_url.txt"
