#!/bin/bash

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
readonly PROJECT_FILE="ZFStatMenus.xcodeproj"
readonly SCHEME="ZFStatMenus"
readonly PRODUCT_NAME="ZFStatMenus"

configuration="Debug"
clean_build=false

usage() {
    cat <<'EOF'
用法：./scripts/build-and-run.sh [选项]

构建 ZFStatMenus，关闭当前运行的旧实例，然后打开刚生成的应用。
只有构建成功后才会关闭旧实例。

选项：
  --configuration <Debug|Release>  构建配置，默认 Debug
  --clean                          构建前执行 clean
  -h, --help                       显示帮助

示例：
  ./scripts/build-and-run.sh
  ./scripts/build-and-run.sh --clean
  ./scripts/build-and-run.sh --configuration Release
EOF
}

fail() {
    echo "错误：$*" >&2
    exit 1
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --configuration)
            [[ $# -ge 2 ]] || fail "--configuration 缺少参数"
            configuration="$2"
            shift 2
            ;;
        --clean)
            clean_build=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            fail "未知参数：$1"
            ;;
    esac
done

case "$configuration" in
    Debug|Release) ;;
    *) fail "--configuration 只支持 Debug 或 Release" ;;
esac

for command_name in xcodebuild open pgrep pkill security defaults awk codesign grep; do
    command -v "$command_name" >/dev/null 2>&1 || fail "缺少命令：$command_name"
done

resolve_development_team() {
    if [[ -n "${ZFSTAT_DEVELOPMENT_TEAM:-}" ]]; then
        validate_development_team "$ZFSTAT_DEVELOPMENT_TEAM"
        printf '%s\n' "$ZFSTAT_DEVELOPMENT_TEAM"
        return
    fi

    local configured_team
    configured_team="$(defaults read com.zfstat.ZFStatMenus.build DevelopmentTeam 2>/dev/null || true)"
    if [[ -n "$configured_team" ]]; then
        validate_development_team "$configured_team"
        printf '%s\n' "$configured_team"
        return
    fi

    local identity_line
    identity_line="$(security find-identity -v -p codesigning 2>/dev/null | awk '/Apple Development:/ { print; exit }')"
    if [[ "$identity_line" =~ \(([A-Z0-9]{10})\)[[:space:]]*$ ]]; then
        printf '%s\n' "${BASH_REMATCH[1]}"
        return
    fi

    fail "未找到 Apple Development 签名证书；请先在 Xcode 登录开发者账号并创建证书，或设置 ZFSTAT_DEVELOPMENT_TEAM"
}

validate_development_team() {
    local value="$1"
    [[ "$value" =~ ^[A-Z0-9]{10}$ ]] || fail "开发团队 ID 必须是 10 位大写字母或数字"
}

readonly derived_data_path="${PROJECT_ROOT}/build/RunDerivedData"
readonly app_path="${derived_data_path}/Build/Products/${configuration}/${PRODUCT_NAME}.app"
readonly development_team="$(resolve_development_team)"

build_actions=(build)
if [[ "$clean_build" == true ]]; then
    build_actions=(clean build)
fi

echo "开始构建：configuration=${configuration}"

cd "$PROJECT_ROOT"
xcodebuild \
    -quiet \
    -project "$PROJECT_FILE" \
    -scheme "$SCHEME" \
    -configuration "$configuration" \
    -destination "generic/platform=macOS" \
    -derivedDataPath "$derived_data_path" \
    -allowProvisioningUpdates \
    DEVELOPMENT_TEAM="$development_team" \
    CODE_SIGN_STYLE=Automatic \
    CODE_SIGN_IDENTITY="Apple Development" \
    CODE_SIGNING_ALLOWED=YES \
    CODE_SIGNING_REQUIRED=YES \
    "${build_actions[@]}"

[[ -d "$app_path" ]] || fail "未找到构建产物：$app_path"

signature_details="$(codesign -dv --verbose=4 "$app_path" 2>&1)"
if ! grep -Fq "TeamIdentifier=${development_team}" <<<"$signature_details"; then
    fail "构建产物没有使用预期的开发团队签名"
fi
if grep -Fq "Signature=adhoc" <<<"$signature_details"; then
    fail "构建产物仍是 ad-hoc 签名"
fi
codesign --verify --deep --strict --verbose=2 "$app_path"

if pgrep -x "$PRODUCT_NAME" >/dev/null 2>&1; then
    echo "关闭旧的 ${PRODUCT_NAME} 实例..."
    pkill -TERM -x "$PRODUCT_NAME" || true

    for _ in {1..20}; do
        if ! pgrep -x "$PRODUCT_NAME" >/dev/null 2>&1; then
            break
        fi
        sleep 0.1
    done

    if pgrep -x "$PRODUCT_NAME" >/dev/null 2>&1; then
        echo "旧实例未及时退出，强制结束..."
        pkill -KILL -x "$PRODUCT_NAME" || true

        for _ in {1..20}; do
            if ! pgrep -x "$PRODUCT_NAME" >/dev/null 2>&1; then
                break
            fi
            sleep 0.1
        done

        if pgrep -x "$PRODUCT_NAME" >/dev/null 2>&1; then
            fail "无法结束旧的 ${PRODUCT_NAME} 实例"
        fi
    fi
fi

echo "打开新构建：${app_path}"
launched=false
for attempt in {1..3}; do
    if open -n "$app_path"; then
        launched=true
        break
    fi

    if [[ "$attempt" -lt 3 ]]; then
        echo "启动请求失败，等待 LaunchServices 后重试（${attempt}/3）..."
        sleep 0.3
    fi
done

[[ "$launched" == true ]] || fail "无法启动新构建：${app_path}"

echo "完成：已构建并启动新的 ${PRODUCT_NAME}。"
