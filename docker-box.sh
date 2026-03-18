#!/bin/bash

API_URL="https://api.github.com/repos/Run-os/docker-box/contents/docker?ref=main"

# 功能：从GitHub获取docker配置列表，用户选择后下载并写入变量
name=""
password=""
DOCKER_DATA=""

# 定义颜色输出函数
readonly RED='\033[31m\033[01m'
readonly GREEN='\033[32m\033[01m'
readonly YELLOW='\033[33m\033[01m'
readonly BLUE='\033[34m\033[01m'
readonly MAGENTA='\033[95m\033[01m'
readonly CYAN='\033[38;2;0;255;255m'
readonly NC='\033[0m'

red() { printf "${RED}[WARNING] %s${NC}\n" "$1"; }
green() { printf "${GREEN}[INFO] %s${NC}\n" "$1"; }
greenline() { printf "${GREEN} %s${NC}\n" "$1"; }
yellow() { printf "${YELLOW}[NOTICE] %s${NC}\n" "$1"; }
blue() { printf "${BLUE}[MESSAGE] %s${NC}\n" "$1"; }
cyan() { printf "${CYAN}%s${NC}\n" "$1"; }

# 解析选项 - 注意path后面需要冒号表示需要参数
while getopts "n:p:d:" opt; do
    case $opt in
        n) name="$OPTARG" ;;
        p) password="$OPTARG" ;;
        d) DOCKER_DATA="$OPTARG" ;;
        ?) echo "用法: $0 -n 用户名 -p 密码 -d 数据路径" && exit 1 ;;
    esac
done

# 检查必要参数
if [ -z "$name" ] || [ -z "$password" ] || [ -z "$DOCKER_DATA" ]; then
    echo "用法: $0 -n 用户名 -p 密码 -d 数据路径"
    exit 1
fi

printf "账号：%s，密码：%s，数据路径：%s\n" "$name" "$password" "$DOCKER_DATA"

# 创建目录函数
ensure_directory() {
    local dir="$1"
    if [ ! -d "$dir" ]; then
        mkdir -p "$dir" || {
            red "创建目录失败: $dir"
            return 1
        }
        green "创建目录: $dir"
    fi
}

# 主函数：获取列表并让用户选择
select_and_install() {
    # 清空输出
    clear
    
    green "正在获取Docker配置列表..."
    
    # 获取API数据
    local json_data
    json_data=$(curl -s "$API_URL")
    
    if [ -z "$json_data" ]; then
        red "获取配置列表失败，请检查网络连接"
        return 1
    fi
    
    # 使用数组存储name和download_url
    declare -a names=()
    declare -a urls=()
    
    # 检查是否有jq
    if command -v jq &> /dev/null; then
        # 使用jq解析
        while IFS= read -r line; do
            names+=("$line")
        done < <(echo "$json_data" | jq -r '.[].name')
        
        while IFS= read -r line; do
            urls+=("$line")
        done < <(echo "$json_data" | jq -r '.[].download_url')
    else
        # 使用Python解析（大多数系统都有Python）
        if command -v python3 &> /dev/null; then
            while IFS= read -r line; do
                names+=("$line")
            done < <(python3 -c "import json,sys; data=json.load(sys.stdin); [print(item['name']) for item in data]" <<< "$json_data")
            
            while IFS= read -r line; do
                urls+=("$line")
            done < <(python3 -c "import json,sys; data=json.load(sys.stdin); [print(item['download_url']) for item in data]" <<< "$json_data")
        elif command -v python &> /dev/null; then
            while IFS= read -r line; do
                names+=("$line")
            done < <(python -c "import json,sys; data=json.load(sys.stdin); [print(item['name']) for item in data]" <<< "$json_data")
            
            while IFS= read -r line; do
                urls+=("$line")
            done < <(python -c "import json,sys; data=json.load(sys.stdin); [print(item['download_url']) for item in data]" <<< "$json_data")
        else
            # 使用grep+sed解析（更可靠的方式）
            local single_line
            single_line=$(echo "$json_data" | tr '\n' ' ')
            
            local i=0
            while IFS= read -r obj; do
                local n
                n=$(echo "$obj" | grep -oP '"name"\s*:\s*"\K[^"]+' || echo "$obj" | sed -n 's/.*"name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
                if [ -n "$n" ]; then
                    names+=("$n")
                fi
                
                local u
                u=$(echo "$obj" | grep -oP '"download_url"\s*:\s*"\K[^"]+' || echo "$obj" | sed -n 's/.*"download_url"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
                if [ -n "$u" ]; then
                    urls+=("$u")
                fi
                
                i=$((i + 1))
            done < <(echo "$json_data" | grep -o '{[^{}]*"name"[^{}]*"download_url"[^{}]*}')
        fi
    fi
    
    # 显示列表
    echo ""
    cyan "========== 可用的Docker配置 =========="
    
    local count=${#names[@]}
    for ((i=0; i<count; i++)); do
        local display_name="${names[$i]%.yaml}"
        printf "%2d. %s\n" $((i+1)) "$display_name"
    done
    
    echo ""
    cyan "======================================"
    
    if [ $count -eq 0 ]; then
        red "未找到任何配置文件"
        return 1
    fi
    
    # 用户选择
    printf "请输入序号选择要安装的Docker配置: "
    read -r choice
    
    # 验证输入
    if ! echo "$choice" | grep -qE '^[0-9]+$'; then
        red "无效输入，请输入数字"
        return 1
    fi
    
    if [ "$choice" -lt 1 ] || [ "$choice" -gt "$count" ]; then
        red "序号超出范围"
        return 1
    fi
    
    # 数组索引从0开始
    local idx=$((choice - 1))
    
    # 获取选择的download_url和name
    local selected_url="${urls[$idx]}"
    local selected_name="${names[$idx]}"
    local display_name="${selected_name%.yaml}"
    
    green "您选择了: $display_name"
    green "正在下载配置文件..."
    green "下载地址: $selected_url"
    
    # 下载yaml内容
    local yaml_content
    yaml_content=$(curl -s "$selected_url")
    
    if [ -z "$yaml_content" ]; then
        red "下载配置文件失败"
        return 1
    fi
    
    # 创建目录 - 使用全局变量DOCKER_DATA
    local target_dir="${DOCKER_DATA}/${display_name}"
    ensure_directory "$target_dir"
    
    # 进入目录
    cd "$target_dir" || {
        red "进入目录失败: $target_dir"
        return 1
    }
    
    # 替换变量并写入docker-compose.yml
    # 使用单引号防止shell展开，然后替换字面量 $name 和 $password
    local final_content
    final_content=$(printf '%s' "$yaml_content" | sed "s/\$name/$name/g" | sed "s/\$password/$password/g")
    
    # 写入文件
    printf '%s\n' "$final_content" > docker-compose.yml
    green "配置文件已保存到: $target_dir/docker-compose.yml"
    
    # 显示配置内容
    echo ""
    cyan "========== 配置内容 =========="
    cat docker-compose.yml
    echo ""
    cyan "=============================="
    
    # 询问是否启动
    printf "是否立即启动容器? (y/n): "
    read -r start_now
    
    if [ "$start_now" = "y" ] || [ "$start_now" = "Y" ]; then
        green "正在启动容器..."
        docker-compose up -d || {
            red "容器启动失败"
            return 1
        }
        green "容器启动成功!"
    fi
}

# 执行主函数
select_and_install
