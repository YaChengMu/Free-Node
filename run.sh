#!/bin/bash
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
    currentmonth=$(date +%-m)
    currentday=$(date +%-d)
}

# 计算前N天的日期函数
calculate_previous_date() {
    local days_to_subtract=$1
    local target_date=$(date -d "$currentyear-$currentmonth_padded-$currentday_padded -$days_to_subtract days" +"%Y %m %d %_m %_d")
    echo $target_date
}

# ===== URL处理函数 =====

# URL解码函数
urldecode() {
    local url_encoded="${1//+/ }"
    printf '%b' "${url_encoded//%/\\\\x}"
}

# URL编码函数（不依赖外部工具）
urlencode() {
    local string="$1"
    local strlen=${#string}
    local encoded=""
    local pos c o
    
    pos=0
    while [ $pos -lt $strlen ]; do
        c=${string:$pos:1}
        case "$c" in
            [-_.~a-zA-Z0-9]) # 这些字符不需要编码
                encoded+="$c"
                ;;
            *)
                printf -v o '%%%02x' "'$c"
                encoded+="$o"
                ;;
        esac
        pos=$((pos + 1))
    done
    echo "$encoded"
}

# 检查URL可用性
check_url_availability() {
    local url="$1"
    # 使用curl检查URL是否可访问
    # -s: 静默模式，不显示进度
    # -L: 跟随重定向
    # -I: 只获取头信息
    # --connect-timeout 10: 连接超时10秒
    # --max-time 20: 总超时20秒
    local status_code=$(curl -s -L -I --connect-timeout 10 --max-time 20 -o /dev/null -w '%{http_code}' "$url")
    
    # 检查状态码是否为200或30x（表示成功或重定向）
    if [[ "$status_code" =~ ^(200|30[0-9])$ ]]; then
        return 0  # URL可用
    else
        return 1  # URL不可用
    fi
}

# 检查单个模板的URL可用性
check_template_urls() {
    local template_key="$1"
    local template="$2"
    local param1_type="$3"
    local param2_type="$4"
    local param3_type="$5"
    local max_days_to_check=7  # 最多检查7天
    
    # 初始化日期变量
    local year=$currentyear
    local month_padded=$currentmonth_padded
    local date_padded=$currentday_padded
    local month_no_zero=$currentmonth
    local date_no_zero=$currentday
    local date_full="${year}${month_padded}$(printf "%02d" $((date_padded)))"
    
    echo "模板[$template_key]: 开始检查URL可用性"
    
    # 检查最近几天的URL (从当天开始)
    for ((i=0; i<max_days_to_check; i++)); do
        # 计算日期 (当天及之前几天)
        if [ $i -gt 0 ]; then
            local date_info=$(calculate_previous_date $i)
            year=$(echo $date_info | cut -d' ' -f1)
            month_padded=$(echo $date_info | cut -d' ' -f2)
            date_padded=$(echo $date_info | cut -d' ' -f3)
            month_no_zero=$(echo $date_info | cut -d' ' -f4)
            date_no_zero=$(echo $date_info | cut -d' ' -f5)
            date_full="${year}${month_padded}$(printf "%02d" $((date_padded)))"
        fi
        
        # 根据参数类型选择对应的值
        local check_param1=$year  # 年份总是相同格式
        
        # 处理月份参数
        case $param2_type in
            "month") local check_param2=$month_padded ;;
            "month_no_zero") local check_param2=$month_no_zero ;;
            "month_padded") local check_param2=$month_padded ;;
            *) local check_param2=$month_no_zero ;;  # 默认使用无前导零
        esac
        
        # 处理日期参数
        case $param3_type in
            "date") local check_param3=$date_padded ;;
            "date_no_zero") local check_param3=$date_no_zero ;;
            "date_padded") local check_param3=$date_padded ;;
            "date_full") local check_param3=$date_full ;;
            *) local check_param3=$date_padded ;;  # 默认使用带前导零的日期
        esac
        
        # 使用printf格式化URL
        local check_url=$(printf "$template" "$check_param1" "$check_param2" "$check_param3")
        
        echo "检查: $check_url"
        if check_url_availability "$check_url"; then
            echo "可用: $check_url"
            echo "$check_url"
            break
        else
            echo "不可用: $check_url"
        fi
        
        # 每检查5天打印一次进度
        if [ $(( (i+1) % 5 )) -eq 0 ]; then
            echo "已检查 $((i+1)) 天，继续搜索..."
        fi
    done
}

# ===== 主程序 =====

# 初始化日期变量
get_current_date

# 定义URL模板结构体
# 格式: "URL模板|年份参数类型|月份参数类型|日期参数类型"
declare -A url_templates
url_templates[1]="https://a.nodeshare.xyz/uploads/%s/%s/%s.yaml|year|month_no_zero|date_full"
url_templates[2]="https://nodefree.githubrowcontent.com/%s/%s/%s.yaml|year|month_padded|date_full"
url_templates[3]="https://free.datiya.com/uploads/%s-clash.yaml|date_full"
url_templates[4]="https://fastly.jsdelivr.net/gh/ripaojiedian/freenode@main/clash"
url_templates[5]="https://www.xrayvip.com/free.yaml"
url_templates[6]="https://ghproxy.net/https://raw.githubusercontent.com/anaer/Sub/main/clash.yaml"
url_templates[7]="https://ghproxy.net/https://raw.githubusercontent.com/Pawdroid/Free-servers/main/sub"
url_templates[8]="https://fastly.jsdelivr.net/gh/zhangkaiitugithub/passcro@main/speednodes.yaml"
url_templates[9]="https://raw.githubusercontent.com/ermaozi/get_subscribe/main/subscribe/clash.yml"
url_templates[10]="https://raw.githubusercontent.com/go4sharing/sub/main/sub.yaml"
url_templates[11]="https://raw.githubusercontent.com/Jsnzkpg/Jsnzkpg/Jsnzkpg/Jsnzkpg"
url_templates[12]="https://raw.githubusercontent.com/ermaozi01/free_clash_vpn/main/subscribe/clash.yml"

# 用于存储每个模板找到的可用URL
declare -A template_valid_urls

echo "========== 开始查找可用节点 =========="

# 创建临时文件存储并行任务结果
temp_file=$(mktemp)

# 并行检查所有模板
for template_key in "${!url_templates[@]}"; do
    # 解析模板和参数
    IFS="|" read -r template param1_type param2_type param3_type <<< "${url_templates[$template_key]}"
    
    # 后台运行检查，结果写入临时文件
    (
        result=$(check_template_urls "$template_key" "$template" "$param1_type" "$param2_type" "$param3_type")
        if [ -n "$result" ] && [[ "$result" != *"开始检查URL可用性"* ]]; then
            echo "${template_key}|${result}" >> "$temp_file"
            echo "使用模板[$template_key]: $result"
        else
            echo "模板[$template_key]: 未找到可用URL" >> "$temp_file"
        fi
    ) &
done

# 等待所有后台进程完成
wait

# 从临时文件加载结果
while IFS="|" read -r template_key result; do
    if [ "$result" != "未找到可用URL" ]; then
        template_valid_urls[$template_key]="$result"
    fi
done < "$temp_file"
rm -f "$temp_file"

echo "========== URL查找完成 =========="

# 统计找到的可用URL数量
found_count=0
for template_key in "${!url_templates[@]}"; do
    if [ -n "${template_valid_urls[$template_key]}" ]; then
        found_count=$((found_count + 1))
    fi
done

# 如果所有模板都未找到可用URL，才使用默认URL
if [ $found_count -eq 0 ]; then
    echo "警告: 所有模板均未找到可用URL，使用默认URL"
    for template_key in "${!url_templates[@]}"; do
        IFS="|" read -r template param1_type param2_type param3_type <<< "${url_templates[$template_key]}"
        
        # 使用当天日期生成默认URL
        date_full_default="${currentyear}${currentmonth_padded}$(printf "%02d" $((currentday_padded)))"
        
        # 根据模板参数数量和类型生成默认URL
        case $template_key in
            1)
                # 模板1: https://a.nodeshare.xyz/uploads/%s/%s/%s.yaml|year|month_no_zero|date_full
                template_valid_urls[$template_key]=$(printf "$template" "$currentyear" "$currentmonth" "$date_full_default")
                ;;
            2)
                # 模板2: https://nodefree.githubrowcontent.com/%s/%s/%s.yaml|year|month_padded|date_full
                template_valid_urls[$template_key]=$(printf "$template" "$currentyear" "$currentmonth_padded" "$date_full_default")
                ;;
            3)
                # 模板3: https://free.datiya.com/uploads/%s-clash.yaml|date_full
                template_valid_urls[$template_key]=$(printf "$template" "$date_full_default")
                ;;
            *)
                # 处理其他模板 - 对于只有一个参数的模板（如模板4）
                if [[ -z "$param2_type" && -z "$param3_type" ]]; then
                    # 只有一个参数的模板，尝试用日期参数
                    template_valid_urls[$template_key]=$(printf "$template" "$date_full_default")
                elif [[ -n "$param1_type" && -n "$param2_type" && -n "$param3_type" ]]; then
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
                    
                    template_valid_urls[$template_key]=$(printf "$template" "$param1_val" "$param2_val" "$param3_val")
                elif [[ -n "$param1_type" && -n "$param2_type" && -z "$param3_type" ]]; then
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
                    
                    template_valid_urls[$template_key]=$(printf "$template" "$param1_val" "$param2_val")
                fi
                ;;
        esac
    done
else
    # 显示最终使用的URL
    for template_key in "${!url_templates[@]}"; do
        if [ -n "${template_valid_urls[$template_key]}" ]; then
            echo "使用模板[$template_key]: ${template_valid_urls[$template_key]}"
        fi
    done
fi

# 收集所有有效的URL到一个数组
valid_urls=()
for template_key in "${!template_valid_urls[@]}"; do
    if [ -n "${template_valid_urls[$template_key]}" ]; then
        valid_urls+=("${template_valid_urls[$template_key]}")
    fi
done

# 使用管道符号(|)连接所有有效URL
combined_urls=$(IFS="|"; echo "${valid_urls[*]}")
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
for url in "${valid_urls[@]}"; do
    echo "  * $url"
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
