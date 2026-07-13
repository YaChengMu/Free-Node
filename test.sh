
#!/bin/bash
#########################################################
# 节点订阅自动获取脚本 - 并行模板版本 (Bash优化版)
# 功能：自动查找可用的节点URL并生成订阅
# 特点：并行检测、超时控制、多模板支持
#########################################################

# ===== 全局变量定义 =====
declare -A url_templates
declare -A template_valid_urls
declare -a valid_urls
declare -a deleted_names

# ===== 日期处理函数 =====

# 获取当前日期（多种格式）
get_current_date() {
    # 使用bash内建日期功能
    currentdate=$(date +%Y%m%d)
    currentyear=$(date +%Y)
    # 包含前导零的月份和日期
    currentmonth_padded=$(date +%m)
    currentday_padded=$(date +%d)
    # 不包含前导零的月份和日期
    currentmonth=$((10#$currentmonth_padded))  # 使用算术扩展去除前导零
    currentday=$((10#$currentday_padded))
}

# 计算前N天的日期函数
calculate_previous_date() {
    local days_to_subtract=$1
    # 使用bash内建日期功能
    local target_date=$(date -d "$currentyear-$currentmonth_padded-$currentday_padded -$days_to_subtract days" +"%Y %m %d %m %d" 2>/dev/null || echo "$currentyear $currentmonth_padded $currentday_padded $currentmonth $currentday")
    echo $target_date
}

# ===== URL处理函数 =====

# URL解码函数
urldecode() {
    local url_encoded="$1"
    # 替换+为空格
    url_encoded=${url_encoded//+/ }
    # 解码%编码的字符
    printf '%b' "${url_encoded//%/\\x}"
}

# URL编码函数（使用bash内建功能）
urlencode() {
    local string="$1"
    local encoded=""
    local pos
    local c
    
    for ((pos=0; pos<${#string}; pos++)); do
        c=${string:$pos:1}
        case "$c" in
            [-_.~a-zA-Z0-9]) # 这些字符不需要编码
                encoded+="$c"
                ;;
            *)
                # 将字符转换为十六进制
                printf -v encoded "%s%%%02X" "$encoded" "'$c"
                ;;
        esac
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
    # --connect-timeout 20: 连接超时20秒
    # --max-time 45: 总超时45秒
    local status_code=$(curl -s -L -I --connect-timeout 20 --max-time 45 -o /dev/null -w '%{http_code}' "$url")
    
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
    local date_full="${year}${month_padded}${date_padded}"
    
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
            date_full="${year}${month_padded}${date_padded}"
        fi
        
        # 根据参数类型选择对应的值
        local check_param1=$year  # 年份总是相同格式
        
        # 处理月份参数
        local check_param2
        case $param2_type in
            "month") check_param2=$month_padded ;;
            "month_no_zero") check_param2=$month_no_zero ;;
            "month_padded") check_param2=$month_padded ;;
            *) check_param2=$month_no_zero ;;  # 默认使用无前导零
        esac
        
        # 处理日期参数
        local check_param3
        case $param3_type in
            "date") check_param3=$date_padded ;;
            "date_no_zero") check_param3=$date_no_zero ;;
            "date_padded") check_param3=$date_padded ;;
            "date_full") check_param3=$date_full ;;
            *) check_param3=$date_padded ;;  # 默认使用带前导零的日期
        esac
        
        # 使用printf格式化URL
        local check_url=""
        # 特殊处理模板
        if [ "$template_key" = "3" ]; then
            # 模板3只需要一个date_full参数
            check_url=$(printf "$template" "$date_full")
        elif [ "$template_key" = "1" ] || [ "$template_key" = "2" ]; then
            # 模板1和2需要三个参数
            check_url=$(printf "$template" "$check_param1" "$check_param2" "$check_param3")
        else
            # 其他模板的处理逻辑
            if [ -z "$param2_type" ] && [ -z "$param3_type" ]; then
                # 只有一个参数的模板
                check_url=$(printf "$template" "$check_param3")
            elif [ -n "$param1_type" ] && [ -n "$param2_type" ] && [ -n "$param3_type" ]; then
                # 三个参数的模板
                check_url=$(printf "$template" "$check_param1" "$check_param2" "$check_param3")
            elif [ -n "$param1_type" ] && [ -n "$param2_type" ] && [ -z "$param3_type" ]; then
                # 两个参数的模板
                check_url=$(printf "$template" "$check_param1" "$check_param2")
            else
                # 默认处理方式
                check_url=$(printf "$template" "$check_param3")
            fi
        fi
        
        # 添加调试信息
        echo "正在检查URL: $check_url (模板 $template_key, 第 $i 天)" >&2
        
        if check_url_availability "$check_url"; then
            echo "$check_url"
            return 0
        fi
        
        # 每检查5天打印一次进度
        local remainder=$(( (i+1) % 5 ))
        if [ $remainder -eq 0 ]; then
            echo "已检查 $((i+1)) 天，继续搜索..." >&2
        fi
    done
    
    # 如果没有找到有效的URL，返回空
    return 1
}

# 并行检查所有模板
check_all_templates_parallel() {
    echo "========== 开始查找可用节点 =========="
    
    # 创建临时目录存储并行任务结果
    local temp_dir=$(mktemp -d)
    
    # 并行检查所有模板
    for key in "${!url_templates[@]}"; do
        local template_info="${url_templates[$key]}"
        local template=$(echo "$template_info" | cut -d'|' -f1)
        local param1_type=$(echo "$template_info" | cut -d'|' -f2)
        local param2_type=$(echo "$template_info" | cut -d'|' -f3)
        local param3_type=$(echo "$template_info" | cut -d'|' -f4)
        
        # 后台运行检查，结果写入临时文件
        (
            result=$(check_template_urls "$key" "$template" "$param1_type" "$param2_type" "$param3_type")
            if [ -n "$result" ]; then
                echo "$result" > "$temp_dir/result_$key"
                echo "检测到有效URL (模板[$key]): $result" >&2
            else
                echo "模板[$key] 未找到有效URL" >&2
            fi
        ) &
    done
    
    # 等待所有后台进程完成
    wait
    
    # 从临时文件加载结果
    for key in "${!url_templates[@]}"; do
        if [ -f "$temp_dir/result_$key" ]; then
            template_valid_urls[$key]=$(cat "$temp_dir/result_$key")
        fi
    done
    
    # 清理临时目录
    rm -rf "$temp_dir"
    
    echo "========== URL查找完成 =========="
}

# ===== 主程序 =====

# 初始化日期变量
get_current_date

# 定义URL模板结构体
# 格式: "URL模板|年份参数类型|月份参数类型|日期参数类型"
#https://raw.githubusercontent.com/Jsnzkpg/Jsnzkpg/Jsnzkpg/Jsnzkpg
#https://fastly.jsdelivr.net/gh/zhangkaiitugithub/passcro@main/speednodes.yaml
#https://www.xrayvip.com/free.yaml
#https://raw.githubusercontent.com/ermaozi01/free_clash_vpn/main/subscribe/clash.yml
#https://fpyjdy.zzong6599.workers.dev
url_templates=(
    [1]="https://a.nodeshare.xyz/uploads/%s/%s/%s.yaml|year|month_no_zero|date_full"
    [2]="https://nodefree.githubrowcontent.com/%s/%s/%s.yaml|year|month_padded|date_full"
    [3]="https://free.datiya.com/uploads/%s-clash.yaml|date_full"
    [4]="https://fastly.jsdelivr.net/gh/ripaojiedian/freenode@main/clash"
    [5]="https://ghproxy.net/https://raw.githubusercontent.com/Pawdroid/Free-servers/main/sub"
    [6]="https://raw.githubusercontent.com/ermaozi/get_subscribe/main/subscribe/clash.yml"
    [7]="https://raw.githubusercontent.com/go4sharing/sub/main/sub.yaml"
    [8]="https://panel.xingvoy.com/api/sub/Pr2uaeZ5o2ad3mgb"
)

# 并行检查所有模板
check_all_templates_parallel

# 统计找到的可用URL数量
found_count=0
for key in "${!template_valid_urls[@]}"; do
    if [ -n "${template_valid_urls[$key]}" ]; then
        found_count=$((found_count + 1))
    fi
done

# 如果所有模板都未找到可用URL，才使用默认URL
if [ $found_count -eq 0 ]; then
    echo "警告: 所有模板均未找到可用URL，使用默认URL"
    
    for key in "${!url_templates[@]}"; do
        template_info="${url_templates[$key]}"
        template=$(echo "$template_info" | cut -d'|' -f1)
        param1_type=$(echo "$template_info" | cut -d'|' -f2)
        param2_type=$(echo "$template_info" | cut -d'|' -f3)
        param3_type=$(echo "$template_info" | cut -d'|' -f4)
        
        # 使用当天日期生成默认URL
        date_full_default="${currentyear}${currentmonth_padded}${currentday_padded}"
        
        # 根据模板参数数量和类型生成默认URL
        url=""
        case $key in
            1)
                # 模板1: https://a.nodeshare.xyz/uploads/%s/%s/%s.yaml|year|month_no_zero|date_full
                url=$(printf "$template" "$currentyear" "$currentmonth" "$date_full_default")
                echo "生成模板1的默认URL: $url" >&2
                ;;
            2)
                # 模板2: https://nodefree.githubrowcontent.com/%s/%s/%s.yaml|year|month_padded|date_full
                url=$(printf "$template" "$currentyear" "$currentmonth_padded" "$date_full_default")
                echo "生成模板2的默认URL: $url" >&2
                ;;
            3)
                # 模板3: https://free.datiya.com/uploads/%s-clash.yaml|date_full
                url=$(printf "$template" "$date_full_default")
                echo "生成模板3的默认URL: $url" >&2
                ;;
            4|7)
                # 模板4和7: 无参数
                url="$template"
                ;;
            *)
                # 处理其他模板 - 对于只有一个参数的模板
                if [ -z "$param2_type" ] && [ -z "$param3_type" ]; then
                    # 只有一个参数的模板，尝试用日期参数
                    url=$(printf "$template" "$date_full_default")
                elif [ -n "$param1_type" ] && [ -n "$param2_type" ] && [ -n "$param3_type" ]; then
                    # 三个参数的模板
                    # 处理年份参数
                    param1_val="$currentyear"
                    
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
                    
                    url=$(printf "$template" "$param1_val" "$param2_val" "$param3_val")
                elif [ -n "$param1_type" ] && [ -n "$param2_type" ] && [ -z "$param3_type" ]; then
                    # 两个参数的模板
                    # 处理第一个参数
                    param1_val="$currentyear"
                    
                    # 处理第二个参数
                    case $param2_type in
                        "month") param2_val="$currentmonth_padded" ;;
                        "month_no_zero") param2_val="$currentmonth" ;;
                        "month_padded") param2_val="$currentmonth_padded" ;;
                        "date_full") param2_val="$date_full_default" ;;
                        *) param2_val="$date_full_default" ;;
                    esac
                    
                    url=$(printf "$template" "$param1_val" "$param2_val")
                fi
                ;;
        esac
        
        # 保存URL
        if [ -n "$url" ]; then
            template_valid_urls[$key]="$url"
        fi
    done
else
    # 显示最终使用的URL
    for key in "${!template_valid_urls[@]}"; do
        if [ -n "${template_valid_urls[$key]}" ]; then
            echo "使用模板[$key]: ${template_valid_urls[$key]}"
            valid_urls+=("${template_valid_urls[$key]}")
        fi
    done
fi

# 如果没有找到有效的URL，则使用默认URL
if [ ${#valid_urls[@]} -eq 0 ]; then
    echo "未找到任何有效URL，使用默认URL"
    
    for key in "${!url_templates[@]}"; do
        template_info="${url_templates[$key]}"
        template=$(echo "$template_info" | cut -d'|' -f1)
        param1_type=$(echo "$template_info" | cut -d'|' -f2)
        param2_type=$(echo "$template_info" | cut -d'|' -f3)
        param3_type=$(echo "$template_info" | cut -d'|' -f4)
            
        # 使用当天日期生成默认URL
        date_full_default="${currentyear}${currentmonth_padded}${currentday_padded}"
            
        # 根据模板参数数量和类型生成默认URL
        url=""
        case $key in
            1)
                # 模板1: https://a.nodeshare.xyz/uploads/%s/%s/%s.yaml|year|month_no_zero|date_full
                url=$(printf "$template" "$currentyear" "$currentmonth" "$date_full_default")
                echo "生成模板1的备用URL: $url" >&2
                ;;
            2)
                # 模板2: https://nodefree.githubrowcontent.com/%s/%s/%s.yaml|year|month_padded|date_full
                url=$(printf "$template" "$currentyear" "$currentmonth_padded" "$date_full_default")
                echo "生成模板2的备用URL: $url" >&2
                ;;
            3)
                # 模板3: https://free.datiya.com/uploads/%s-clash.yaml|date_full
                url=$(printf "$template" "$date_full_default")
                echo "生成模板3的备用URL: $url" >&2
                ;;
            4|7)
                # 模板4和7: 无参数
                url="$template"
                ;;
            *)
                # 处理其他模板 - 对于只有一个参数的模板
                if [ -z "$param2_type" ] && [ -z "$param3_type" ]; then
                    # 只有一个参数的模板，尝试用日期参数
                    url=$(printf "$template" "$date_full_default")
                elif [ -n "$param1_type" ] && [ -n "$param2_type" ] && [ -n "$param3_type" ]; then
                    # 三个参数的模板
                    # 处理年份参数
                    param1_val="$currentyear"
                        
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
                        
                    url=$(printf "$template" "$param1_val" "$param2_val" "$param3_val")
                elif [ -n "$param1_type" ] && [ -n "$param2_type" ] && [ -z "$param3_type" ]; then
                    # 两个参数的模板
                    # 处理第一个参数
                    param1_val="$currentyear"
                        
                    # 处理第二个参数
                    case $param2_type in
                        "month") param2_val="$currentmonth_padded" ;;
                        "month_no_zero") param2_val="$currentmonth" ;;
                        "month_padded") param2_val="$currentmonth_padded" ;;
                        "date_full") param2_val="$date_full_default" ;;
                        *) param2_val="$date_full_default" ;;
                    esac
                        
                    url=$(printf "$template" "$param1_val" "$param2_val")
                fi
                ;;
        esac
            
        # 保存URL
        if [ -n "$url" ]; then
            template_valid_urls[$key]="$url"
            valid_urls+=("$url")
        fi
    done
fi

# 使用管道符号(|)连接所有有效URL
combined_urls=$(IFS='|'; echo "${valid_urls[*]}")
echo "合并URL: $combined_urls"

# 不对URL进行额外编码，直接使用原始URL
encoded_combined_urls="$combined_urls"
echo "编码后URL: $encoded_combined_urls"

# 构建订阅链接
echo "========== 生成订阅链接 =========="
subscribeclash="https://suc-jp.bihai.site/sub?target=clash&url=$encoded_combined_urls&insert=false&config=https%3A%2F%2Fraw.githubusercontent.com%2Fzsokami%2FACL4SSR%2Frefs%2Fheads%2Fmain%2FACL4SSR_Online_Full_Mannix_No_DNS_Leak.ini&exclude=聖荷西|西班牙|到期|注册|费率|星航VPN|->&filename=GitHub-GetNode&emoji=true&sort=true&udp=true"
subscribeV2ray="https://suc-jp.bihai.site/sub?target=v2ray&url=$encoded_combined_urls&insert=false&config=https%3A%2F%2Fraw.githubusercontent.com%2Fzsokami%2FACL4SSR%2Frefs%2Fheads%2Fmain%2FACL4SSR_Online_Full_Mannix_No_DNS_Leak.ini&exclude=聖荷西|西班牙|到期|注册|费率|星航VPN|->&filename=GitHub-GetNode&emoji=true&sort=true&udp=true"

# 打印完整的订阅链接参数
echo "========== 订阅链接详情 =========="
echo "Clash订阅链接:"
echo "$subscribeclash" | fold -w 80

# 解析并打印订阅链接的各个参数
echo ""
echo "订阅链接参数解析:"
echo "- 目标格式: clash"
echo "- 源URL列表: "

# 显示所有有效的URL
valid_url_count=0
for key in "${!template_valid_urls[@]}"; do
    if [ -n "${template_valid_urls[$key]}" ]; then
        echo "  * ${template_valid_urls[$key]}"
        valid_url_count=$((valid_url_count + 1))
    fi
done

# 如果没有找到任何有效URL，显示提示信息
if [ $valid_url_count -eq 0 ]; then
    echo "  * 未找到有效URL"
fi

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

# 定义下载函数，带重试机制
download_with_retry() {
    local url="$1"
    local output_file="$2"
    local description="$3"
    local max_retries=3
    local retry_count=0
    
    while [ $retry_count -lt $max_retries ]; do
        echo "下载${description} (尝试 $((retry_count+1))/$max_retries)..."
        if wget --timeout=90 --tries=1 --user-agent="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36" -q "$url" -O "$output_file"; then
            echo "${description}下载成功"
            return 0
        else
            local exit_code=$?
            echo "${description}下载失败，退出码: $exit_code"
            retry_count=$((retry_count+1))
            if [ $retry_count -lt $max_retries ]; then
                echo "等待5秒后重试..."
                sleep 5
            fi
        fi
    done
    
    # 最终尝试显示详细错误信息
    echo "最终尝试获取详细错误信息:"
    wget --timeout=90 --tries=1 --user-agent="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36" -S "$url" -O "$output_file" 2>&1 | head -20
    return 1
}

# 下载Clash配置
if download_with_retry "$subscribeclash" "./clash.yaml" "Clash配置"; then
    echo "Clash配置下载完成"
else
    echo "Clash配置下载最终失败"
    # 如果文件存在但下载失败，检查文件内容
    if [ -f "./clash.yaml" ]; then
        echo "检查下载的文件内容:"
        head -10 ./clash.yaml
    fi
fi

# 下载V2Ray配置
if download_with_retry "$subscribeV2ray" "./v2ray.txt" "V2Ray配置"; then
    echo "V2Ray配置下载完成"
else
    echo "V2Ray配置下载最终失败"
    # 如果文件存在但下载失败，检查文件内容
    if [ -f "./v2ray.txt" ]; then
        echo "检查下载的文件内容:"
        head -10 ./v2ray.txt
    fi
fi

# 处理下载的clash.yaml文件
echo "========== 处理clash.yaml文件 =========="
# 创建临时文件
temp_file=$(mktemp)

# 初始化状态变量
in_proxy=0
in_proxy_groups=0
in_current_proxy=0
in_proxies_list=0
in_url_test_group=0
remove_current=0
current_server=""
current_port=""
proxy_content=""
servers_seen=""
valid_names=""
current_group_name=""
current_group_type=""

# 打印初始去重信息
echo "开始处理clash.yaml文件，初始去重状态:" >&2
echo "servers_seen: $servers_seen" >&2
echo "valid_names: $valid_names" >&2

# 逐行处理clash.yaml文件
while IFS= read -r line; do
    # 检查是否是proxies部分开始
    if [[ "$line" =~ ^proxies:$ ]]; then
        in_proxy=1
        in_proxy_groups=0
        in_proxies_list=0
        in_url_test_group=0
        echo "$line"
        continue
    fi
    
    # 检查是否是proxy-groups部分开始
    if [[ "$line" =~ ^proxy-groups:$ ]]; then
        in_proxy=0
        in_proxy_groups=1
        in_proxies_list=0
        in_url_test_group=0
        echo "$line"
        continue
    fi
    
    # 处理proxies部分
    if [ $in_proxy -eq 1 ]; then
        # 检查是否是新节点开始
        if [[ "$line" =~ ^\ \ -\  ]]; then
            # 处理上一个节点（如果存在）
            if [ $in_current_proxy -eq 1 ]; then
                if [ $remove_current -eq 0 ]; then
                    # 检查是否已存在相同server和port的节点（忽略大小写）
                    is_duplicate=0
                    if [ -n "$current_server" ] && [ -n "$current_port" ]; then
                        # 转换为小写进行比较
                        lowercase_server=$(echo "$current_server" | tr '[:upper:]' '[:lower:]')
                        if [[ " $servers_seen " =~ " $lowercase_server:$current_port " ]]; then
                            is_duplicate=1
                        fi
                    fi
                    
                    if [ $is_duplicate -eq 0 ]; then
                        # server和port未同时出现过，输出节点
                        echo "$proxy_content"
                        # 记录server:port组合（使用小写server）
                        if [ -n "$current_server" ] && [ -n "$current_port" ]; then
                            lowercase_server=$(echo "$current_server" | tr '[:upper:]' '[:lower:]')
                            servers_seen="$servers_seen $lowercase_server:$current_port"
                            echo "添加节点: $current_server:$current_port" >&2
                        fi
                        # 记录有效的节点名称
                        if [[ "$proxy_content" =~ name:\ ([^,}]*) ]]; then
                            node_name="${BASH_REMATCH[1]}"
                            # 使用引号包围节点名称以处理特殊字符
                            valid_names="$valid_names \"$node_name\""
                            echo "记录有效节点名称: $node_name" >&2
                        fi
                    else
                        # 记录被删除的重复节点名称
                        echo "发现重复节点: $current_server:$current_port" >&2
                        if [[ "$proxy_content" =~ name:\ ([^,}]*) ]]; then
                            node_name="${BASH_REMATCH[1]}"
                            # 使用引号包围节点名称以处理特殊字符
                            deleted_names+=("$node_name")
                            echo "删除重复节点名称: $node_name" >&2
                        fi
                    fi
                else
                    # 记录被删除的无效节点名称
                    if [[ "$proxy_content" =~ name:\ ([^,}]*) ]]; then
                        node_name="${BASH_REMATCH[1]}"
                        # 使用引号包围节点名称以处理特殊字符
                        deleted_names+=("$node_name")
                        echo "删除无效节点名称: $node_name" >&2
                    fi
                fi
            fi
            
            # 重置状态以处理新节点
            in_current_proxy=1
            proxy_content="$line"
            current_server=""
            current_port=""
            remove_current=0
            
            # 检查是否包含 cipher: "" 或 password: ""
            if [[ "$line" =~ cipher:\ \"\" ]] || [[ "$line" =~ password:\ \"\" ]]; then
                remove_current=1
            fi
            
            # 尝试提取server和port
            if [[ "$line" =~ server:\ ([^,}]*) ]]; then
                current_server="${BASH_REMATCH[1]}"
            fi
            if [[ "$line" =~ port:\ ([^,}]*) ]]; then
                current_port="${BASH_REMATCH[1]}"
            fi
            continue
        fi
        
        # 在节点内容中
        if [ $in_current_proxy -eq 1 ]; then
            proxy_content="$proxy_content"$'\n'"$line"
            
            # 继续检查是否需要删除当前节点
            if [ $remove_current -eq 0 ]; then
                if [[ "$line" =~ cipher:\ \"\" ]] || [[ "$line" =~ password:\ \"\" ]]; then
                    remove_current=1
                fi
            fi
            
            # 继续尝试提取server和port
            if [ -z "$current_server" ]; then
                if [[ "$line" =~ server:\ ([^,}]*) ]]; then
                    current_server="${BASH_REMATCH[1]}"
                fi
            fi
            if [ -z "$current_port" ]; then
                if [[ "$line" =~ port:\ ([^,}]*) ]]; then
                    current_port="${BASH_REMATCH[1]}"
                fi
            fi
            continue
        fi
        
        # proxies部分结束
        if [[ "$line" =~ ^[^[:space:]] ]] && ! [[ "$line" =~ ^[[:space:]] ]]; then
            # 处理最后一个节点
            if [ $in_current_proxy -eq 1 ] && [ $remove_current -eq 0 ]; then
                # 检查是否已存在相同server和port的节点（忽略大小写）
                is_duplicate=0
                if [ -n "$current_server" ] && [ -n "$current_port" ]; then
                    # 转换为小写进行比较
                    lowercase_server=$(echo "$current_server" | tr '[:upper:]' '[:lower:]')
                    if [[ " $servers_seen " =~ " $lowercase_server:$current_port " ]]; then
                        is_duplicate=1
                    fi
                fi
                
                if [ $is_duplicate -eq 0 ]; then
                    # server和port未同时出现过，输出节点
                    echo "$proxy_content"
                    # 记录server:port组合（使用小写server）
                    if [ -n "$current_server" ] && [ -n "$current_port" ]; then
                        lowercase_server=$(echo "$current_server" | tr '[:upper:]' '[:lower:]')
                        servers_seen="$servers_seen $lowercase_server:$current_port"
                        echo "添加节点: $current_server:$current_port" >&2
                    fi
                    # 记录有效的节点名称
                    if [[ "$proxy_content" =~ name:\ ([^,}]*) ]]; then
                        node_name="${BASH_REMATCH[1]}"
                        # 使用引号包围节点名称以处理特殊字符
                        valid_names="$valid_names \"$node_name\""
                        echo "记录有效节点名称: $node_name" >&2
                    fi
                else
                    # 记录被删除的重复节点名称
                    echo "发现重复节点: $current_server:$current_port" >&2
                    if [[ "$proxy_content" =~ name:\ ([^,}]*) ]]; then
                        node_name="${BASH_REMATCH[1]}"
                        # 使用引号包围节点名称以处理特殊字符
                        deleted_names+=("$node_name")
                        echo "删除重复节点名称: $node_name" >&2
                    fi
                fi
            elif [ $in_current_proxy -eq 1 ] && [ $remove_current -eq 1 ]; then
                # 记录被删除的无效节点名称
                if [[ "$proxy_content" =~ name:\ ([^,}]*) ]]; then
                    node_name="${BASH_REMATCH[1]}"
                    # 使用引号包围节点名称以处理特殊字符
                    deleted_names+=("$node_name")
                    echo "删除无效节点名称: $node_name" >&2
                fi
            fi
            
            # 结束proxies部分处理
            in_proxy=0
            in_current_proxy=0
            echo "$line"
            continue
        fi
        
        # proxies部分的其他行
        echo "$line"
        continue
    fi
    
    # 处理proxy-groups部分
    if [ $in_proxy_groups -eq 1 ]; then
        # 检查是否是新的group开始 (以两个空格开头后跟字母)
        if [[ "$line" =~ ^\ \ [a-zA-Z] ]]; then
            # 重置状态变量
            in_proxies_list=0
            in_url_test_group=0
            current_group_type=""
            # 重置计数器
            current_group_proxy_count=0
            current_group_valid_proxy_count=0
            echo "$line"
            continue
        fi
        
        # 获取当前group的名称
        if [[ "$line" =~ ^\ \ -\ name:\ (.*) ]]; then
            # 直接获取名称
            current_group_name="${BASH_REMATCH[1]}"
            # 去除可能存在的前后引号和尾部空格
            current_group_name=$(echo "$current_group_name" | sed 's/^"\(.*\)"$/\1/' | sed 's/[[:space:]]*$//')
            echo "$line"
            continue
        fi
        
        # 检查group类型
        if [[ "$line" =~ ^\ \ \ \ type:\ url-test ]]; then
            in_url_test_group=1
            current_group_type="url-test"
            echo "$line"
            continue
        fi
        
        # 检查是否是proxies列表开始
        if [[ "$line" =~ ^\ \ \ \ proxies:$ ]]; then
            in_proxies_list=1
            # 重置组内代理计数器
            current_group_proxy_count=0
            current_group_valid_proxy_count=0
            echo "$line"
            continue
        fi
        
        # 定义需要检查节点有效性的proxy-group名称集合
        special_group_names="\"⚡ ‍低延迟\" \"👆🏻 ‍指定\" \"🇭🇰 ‍香港\" \"🇹🇼 ‍台湾\" \"🇨🇳 ‍中国\" \"🇸🇬 ‍新加坡\" \"🇯🇵 ‍日本\" \"🇺🇸 ‍美国\" \"🎏 ‍其他\" \"👆🏻🇭🇰 ‍香港\" \"👆🏻🇹🇼 ‍台湾\" \"👆🏻🇨🇳 ‍中国\" \"👆🏻🇸🇬 ‍新加坡\" \"👆🏻🇯🇵 ‍日本\" \"👆🏻🇺🇸 ‍美国\" \"👆🏻🎏 ‍其他\""
        
        # 如果在proxies列表中
        if [ "$in_proxies_list" = "1" ]; then
            # 检查是否是proxies列表条目 (以"      - "开头)
            if [[ "$line" =~ ^\ \ \ \ \ \ -\  ]]; then
                # 提取proxy名称
                proxy_name=""
                if [[ "$line" =~ ^\ \ \ \ \ \ -\ [^{] ]]; then
                    # 处理普通格式: "      - ProxyName"
                    # 使用更简单直接的方法提取节点名称，保留完整内容包括空格和特殊字符
                    proxy_name=$(echo "$line" | sed 's/^      - //' | sed 's/ *#.*//' | sed 's/ *$//')
                elif [[ "$line" =~ ^\ \ \ \ \ \ -\{name:(.*) ]]; then
                    # 处理内联格式: "      - {name: ProxyName, ...}"
                    if [[ "$line" =~ name:\ ([^,}]*) ]]; then
                        proxy_name="${BASH_REMATCH[1]}"
                    fi
                fi
                
                # 更新组内代理计数
                current_group_proxy_count=$((current_group_proxy_count + 1))
                
                # 检查是否需要验证节点有效性
                need_check_validity=0
                
                # 对于url-test类型的group，需要检查节点有效性
                if [ "$in_url_test_group" = "1" ]; then
                    need_check_validity=1
                # 对于非url-test类型但name在指定集合中的group，需要检查节点有效性
                # 使用更宽松的匹配方式
                elif echo " $special_group_names " | grep -q " $current_group_name "; then
                    need_check_validity=1
                fi
                
                # 如果需要检查节点有效性
                if [ "$need_check_validity" = "1" ]; then
                    if [ -n "$proxy_name" ]; then
                        # 检查是否在有效节点列表中，使用引号包围确保精确匹配
                        if [[ " $valid_names " =~ " \"$proxy_name\" " ]]; then
                            current_group_valid_proxy_count=$((current_group_valid_proxy_count + 1))
                            echo "$line"
                        else
                            # 真正跳过输出该行
                            continue
                        fi
                        continue
                    fi
                    current_group_valid_proxy_count=$((current_group_valid_proxy_count + 1))
                    echo "$line"
                else
                    # 不需要检查节点有效性，直接输出
                    current_group_valid_proxy_count=$((current_group_valid_proxy_count + 1))
                    echo "$line"
                fi
                continue
            else
                # 不是proxies列表条目，可能是结束或其他属性
                # 检查proxies列表是否即将结束（遇到非缩进行或组内其他属性）
                if [[ "$line" =~ ^\ \ \ \ [a-zA-Z] ]]; then
                    in_proxies_list=0
                    in_url_test_group=0
                    
                    # 检查是否是特殊组且没有有效代理节点，如果有则添加fallback
                    if echo " $special_group_names " | grep -q " $current_group_name " && [ $current_group_valid_proxy_count -eq 0 ]; then
                        # 如果特殊组没有有效代理，添加一个fallback或DIRECT作为占位符
                        echo "      - DIRECT"
                        echo "      # 注意: 原本的节点已被过滤，此处添加DIRECT作为占位符以避免配置错误"
                    fi
                fi
            fi
            echo "$line"
            continue
        fi

        # 输出其他行
        echo "$line"
        continue
    fi
    
    # 处理其他部分
    echo "$line"
done < ./clash.yaml > "$temp_file"

# 移动临时文件到原文件
mv "$temp_file" ./clash.yaml

# 打印最终去重信息
echo "Clash配置已清理完成" >&2
echo "最终去重状态:" >&2
echo "servers_seen: $servers_seen" >&2
echo "valid_names: $valid_names" >&2
echo "deleted_names: ${deleted_names[*]}" >&2

echo "========== 任务完成 =========="
echo "生成的文件:"
echo "1. clash.yaml - Clash配置文件"
echo "2. v2ray.txt - V2Ray配置文件"
echo "3. clash_subscribe_url.txt - Clash订阅链接"
echo ""
echo "可以使用以下命令查看完整的订阅链接:"
echo "cat ./clash_subscribe_url.txt"
