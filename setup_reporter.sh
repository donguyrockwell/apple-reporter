#!/bin/bash
#
# setup_reporter.sh: Apple Reporter 도구 통합 설치 및 자동화 설정 스크립트 (v2.2 - 수정됨)
#
# [기능 요약]
# 1. OS 감지 (Ubuntu/Debian 및 CentOS/RHEL 지원)
# 2. Java 1.8 이상 버전 확인 및 자동 설치
# 3. 필수 유틸리티 (wget, unzip, mail) 확인 및 설치
# 4. Apple Reporter.jar 다운로드 및 설치 (/opt/apple_reporter)
# 5. 액세스 토큰(Access Token) 입력 및 설정 파일(properties) 구성
# 6. 벤더(Vendor) ID 입력 및 설정 저장
# 7. 재무 보고서(Financial Report) 자동 다운로드 스크립트 생성

# --- 전역 변수 및 경로 설정 ---
BASE_DIR="/opt/apple_reporter"
BIN_DIR="$BASE_DIR/bin"
LOG_DIR="$BASE_DIR/logs"
REPORTS_DIR="$BASE_DIR/reports"
SALES_DIR="$REPORTS_DIR/sales"
FINANCIAL_DIR="$REPORTS_DIR/financial"
VENDOR_CONF_FILE="$BIN_DIR/vendor.conf"

# 색상 코드 (터미널 출력용)
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# --- OS 감지용 변수 ---
OS_ID=""
PKG_MANAGER=""
PKG_UPDATE_CMD=""
PKG_INSTALL_CMD=""
JAVA_PKG=""
UTILS_PKGS=""

# 로깅 헬퍼 함수
fn_log_info() { echo -e "${GREEN}[INFO] $1${NC}"; }
fn_log_warn() { echo -e "${YELLOW}[WARN] $1${NC}"; }
fn_log_error() { echo -e "${RED}[ERROR] $1${NC}" >&2; }

# --- 1. OS 감지 및 패키지 관리자 설정 ---
fn_detect_os() {
    fn_log_info "운영체제(OS)를 감지합니다..."
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS_ID=$ID
    else
        fn_log_error "/etc/os-release 파일을 찾을 수 없어 OS를 식별할 수 없습니다."
        exit 1
    fi

    case $OS_ID in
        ubuntu|debian)
            PKG_MANAGER="apt-get"
            PKG_UPDATE_CMD="sudo apt-get update"
            PKG_INSTALL_CMD="sudo apt-get install -y"
            JAVA_PKG="default-jre"
            UTILS_PKGS="wget unzip mailutils"
            ;;
        centos|rhel|fedora|rocky|almalinux)
            if command -v dnf >/dev/null; then
                PKG_MANAGER="dnf"
            elif command -v yum >/dev/null; then
                PKG_MANAGER="yum"
            else
                fn_log_error "RHEL 계열 OS에서 yum 또는 dnf를 찾을 수 없습니다."
                exit 1
            fi
            PKG_UPDATE_CMD="" # yum/dnf는 install 시 메타데이터 자동 갱신
            PKG_INSTALL_CMD="sudo $PKG_MANAGER install -y"
            JAVA_PKG="java-1.8.0-openjdk"
            UTILS_PKGS="wget unzip mailx"
            ;;
        *)
            fn_log_error "지원되지 않는 OS입니다: $OS_ID. 수동 설치가 필요합니다."
            exit 1
            ;;
    esac
    fn_log_info "감지된 OS: $OS_ID, 패키지 관리자: $PKG_MANAGER"
}

# --- 2. Java 런타임 확인 및 설치 ---
fn_check_java() {
    fn_log_info "Java 1.8 이상 버전 설치 여부를 확인합니다..."
    local NEEDS_INSTALL=0
    
    if type -p java >/dev/null; then
        JAVA_VERSION=$(java -version 2>&1 | awk -F '"' '/version/ {print $2}')
        # 버전 문자열 파싱 (예: 1.8.0_xxx -> 1, 8)
        VERSION_MAJOR=$(echo "$JAVA_VERSION" | cut -d. -f1)
        VERSION_MINOR=$(echo "$JAVA_VERSION" | cut -d. -f2)

        if [ "$VERSION_MAJOR" -eq 1 ] && [ "$VERSION_MINOR" -lt 8 ]; then
            fn_log_warn "현재 Java 버전($JAVA_VERSION)이 1.8 미만입니다. 업데이트를 시도합니다."
            NEEDS_INSTALL=1
        else
            fn_log_info "Java $JAVA_VERSION (1.8 이상)이 이미 설치되어 있습니다."
        fi
    else
        fn_log_warn "Java가 설치되어 있지 않습니다. 설치를 진행합니다."
        NEEDS_INSTALL=1
    fi

    if [ "$NEEDS_INSTALL" -eq 1 ]; then
        fn_install_java
    fi
}

fn_install_java() {
    fn_log_info "[$OS_ID] Java 패키지($JAVA_PKG)를 설치합니다..."
    if [ -n "$PKG_UPDATE_CMD" ]; then
        $PKG_UPDATE_CMD || fn_log_warn "패키지 목록 업데이트 중 오류가 발생했지만 계속 진행합니다."
    fi
    
    if ! $PKG_INSTALL_CMD $JAVA_PKG; then
        fn_log_error "Java 설치 실패. 스크립트를 중단합니다."
        exit 1
    fi

    if type -p java >/dev/null; then
        fn_log_info "Java 설치가 완료되었습니다."
    else
        fn_log_error "Java 설치 후 확인에 실패했습니다."
        exit 1
    fi
}

# --- 3. 필수 유틸리티 확인 (wget, unzip, mail) ---
fn_check_utils() {
    fn_log_info "필수 유틸리티 설치 여부를 확인합니다..."
    local missing_utils=0
    if ! command -v wget >/dev/null; then missing_utils=1; fi
    if ! command -v unzip >/dev/null; then missing_utils=1; fi
    if ! command -v mail >/dev/null; then missing_utils=1; fi

    if [ "$missing_utils" -eq 1 ]; then
        fn_log_info "미설치된 유틸리티가 있습니다. 설치를 진행합니다: $UTILS_PKGS"
        if [ -n "$PKG_UPDATE_CMD" ]; then
            $PKG_UPDATE_CMD || true
        fi
        if ! $PKG_INSTALL_CMD $UTILS_PKGS; then
            fn_log_error "유틸리티 설치 실패."
            exit 1
        fi
    else
        fn_log_info "모든 필수 유틸리티가 이미 설치되어 있습니다."
    fi
}

# --- 4. 디렉터리 구조 생성 ---
fn_create_directories() {
    fn_log_info "설치 경로를 생성합니다: $BASE_DIR"
    sudo mkdir -p "$BIN_DIR"
    sudo mkdir -p "$LOG_DIR"
    sudo mkdir -p "$SALES_DIR"
    sudo mkdir -p "$FINANCIAL_DIR"
    fn_log_info "디렉터리 생성 완료."
}

# --- 5. Reporter.jar 다운로드 및 배치 ---
fn_get_reporter_files() {
    fn_log_info "Apple 서버에서 Reporter 도구를 다운로드합니다..."
    local REPORTER_URL="https://itunespartner.apple.com/assets/downloads/Reporter.zip"
    
    # 임시 디렉터리 생성 (mktemp 사용)
    local TMP_DIR
    TMP_DIR=$(mktemp -d /tmp/reporter.XXXXXX)
    
    # 스크립트 종료/중단 시 임시 파일 삭제 트랩 설정
    trap 'rm -rf "$TMP_DIR"; exit 1' 1 2 3 15

    local TMP_ZIP="$TMP_DIR/Reporter.zip"
    local TMP_UNZIP_DIR="$TMP_DIR/Reporter_unzipped"

    if ! wget -q -O "$TMP_ZIP" "$REPORTER_URL"; then
        fn_log_error "다운로드 실패. URL을 확인하세요: $REPORTER_URL"
        rm -rf "$TMP_DIR"
        exit 1
    fi

    if ! unzip -q -o "$TMP_ZIP" -d "$TMP_UNZIP_DIR"; then
        fn_log_error "압축 해제 실패."
        rm -rf "$TMP_DIR"
        exit 1
    fi

    # 파일 찾기 및 이동
    local JAR_FILE=$(find "$TMP_UNZIP_DIR" -name "Reporter.jar" | head -n 1)
    local PROP_FILE=$(find "$TMP_UNZIP_DIR" -name "Reporter.properties" | head -n 1)

    if [ -z "$JAR_FILE" ] || [ -z "$PROP_FILE" ]; then
        fn_log_error "압축 해제된 내용에서 필수 파일을 찾을 수 없습니다."
        rm -rf "$TMP_DIR"
        exit 1
    fi

    fn_log_info "파일을 설치 경로($BIN_DIR)로 이동합니다."
    sudo mv "$JAR_FILE" "$BIN_DIR/Reporter.jar"
    sudo mv "$PROP_FILE" "$BIN_DIR/Reporter.properties.template" # 원본 템플릿으로 저장
    sudo chmod 644 "$BIN_DIR/Reporter.properties.template"

    rm -rf "$TMP_DIR"
    trap - 1 2 3 15 # 트랩 해제
    fn_log_info "Reporter 설치 완료."
}

# --- 6. 환경 설정 (액세스 토큰 입력) ---
# [수정됨] 문법 오류(줄바꿈) 수정 완료
fn_configure_properties() {
    fn_log_info "Reporter.properties 설정을 시작합니다."
    fn_log_warn "App Store Connect에서 생성한 'Access Token'이 필요합니다."
    
    local USER_TOKEN
    local TEMPLATE_FILE="$BIN_DIR/Reporter.properties.template"
    local CONFIG_FILE="$BIN_DIR/Reporter.properties"

    echo ""
    read -p ">> Access Token을 붙여넣기 하세요: " USER_TOKEN
    echo ""

    if [ -z "$USER_TOKEN" ]; then
        fn_log_error "토큰이 입력되지 않았습니다. 스크립트를 종료합니다."
        exit 1
    fi

    if [ ! -f "$TEMPLATE_FILE" ]; then
        fn_log_error "템플릿 파일이 없습니다: $TEMPLATE_FILE"
        exit 1
    fi

    fn_log_info "설정 파일을 생성합니다..."
    sudo cp "$TEMPLATE_FILE" "$CONFIG_FILE"

    # sed를 사용하여 AccessToken 치환 (구분자로 콤마 사용)
    if ! sudo sed -i "s,^#\?AccessToken=.*,AccessToken=$USER_TOKEN," "$CONFIG_FILE"; then
        fn_log_error "설정 파일 수정(sed) 중 오류 발생."
        exit 1
    fi

    sudo chmod 644 "$CONFIG_FILE"
    fn_log_info "설정 파일 구성 완료."
}

# --- 7. 벤더 ID 입력 ---
fn_get_vendor_ids() {
    fn_log_info "자동화에 사용할 벤더(Vendor) ID를 설정합니다."
    fn_log_info "여러 개의 ID가 있다면 공백(스페이스)으로 구분하여 입력하세요."
    fn_log_info "예: 80012345 80067890"
    
    local VENDOR_LIST
    echo ""
    read -p ">> 벤더 ID 입력: " VENDOR_LIST

    if [ -z "$VENDOR_LIST" ]; then
        fn_log_error "벤더 ID가 입력되지 않았습니다."
        exit 1
    fi

    echo "VENDORS=\"$VENDOR_LIST\"" | sudo tee "$VENDOR_CONF_FILE" > /dev/null
    sudo chmod 644 "$VENDOR_CONF_FILE"
    fn_log_info "벤더 ID 저장 완료 ($VENDOR_CONF_FILE)"
}

# --- 8. 재무 보고서(Financial) 다운로드 스크립트 생성 ---
fn_create_scripts() {
    fn_log_info "자동화 스크립트(download_financial.sh)를 생성합니다..."
    
    # 스크립트 파일 내용 작성 (heredoc 사용)
    sudo tee "$BIN_DIR/download_financial.sh" > /dev/null << 'EOF'
#!/bin/bash
#
# download_financial.sh
# 기능: 지난달의 재무 보고서(Financial Report)를 자동으로 다운로드합니다.
# Apple의 회계 연도(Fiscal Year)를 계산하여 올바른 파라미터를 요청합니다.
#

BASE_DIR="/opt/apple_reporter/bin"
JAR_FILE="Reporter.jar"
PROP_FILE="Reporter.properties"
DOWNLOAD_DIR="/opt/apple_reporter/reports/financial"
VENDOR_CONF="/opt/apple_reporter/bin/vendor.conf"

# !!! 중요: 관리자 이메일 주소를 반드시 수정하세요 !!!
ADMIN_EMAIL="admin@example.com"

# 벤더 설정 로드
if [ ! -f "$VENDOR_CONF" ]; then
    echo "$(date): [오류] 벤더 설정 파일($VENDOR_CONF)이 없습니다."
    exit 1
fi
source "$VENDOR_CONF"

# 보고서 타입 설정
REGION="ZZ" # 전 세계 통합 리포트
TYPE="Financial"

# --- Apple 회계 기간 계산 로직 ---
# 지난달의 실제 연도/월을 구함
GREGORIAN_YEAR=$(date -d "last month" +%Y)
GREGORIAN_MONTH_STR=$(date -d "last month" +%m)
GREGORIAN_MONTH_INT=$((10#$GREGORIAN_MONTH_STR))

# Apple 회계 연도는 10월에 시작함
FISCAL_YEAR=$GREGORIAN_YEAR
FISCAL_PERIOD=0

if [ $GREGORIAN_MONTH_INT -ge 10 ]; then
    # 10, 11, 12월은 내년 회계연도의 1, 2, 3분기임
    FISCAL_YEAR=$((GREGORIAN_YEAR + 1))
    FISCAL_PERIOD=$((GREGORIAN_MONTH_INT - 9))
else
    # 1~9월은 현재 회계연도의 4~12분기임
    FISCAL_PERIOD=$((GREGORIAN_MONTH_INT + 3))
fi

TARGET_YEAR=$FISCAL_YEAR
TARGET_MONTH=$FISCAL_PERIOD

OVERALL_SUCCESS=0

# 실행 디렉터리로 이동
cd "$BASE_DIR" || { echo "오류: $BASE_DIR 이동 실패"; exit 1; }

for VENDOR in $VENDORS; do
    echo "--- $(date): 벤더 $VENDOR 처리 중 (회계기간: $TARGET_YEAR-$TARGET_MONTH) ---"
    
    FILENAME="${VENDOR}_${REGION}_${TYPE}_${TARGET_YEAR}_${TARGET_MONTH}.gz"
    EXPECTED_FILE_IN_CWD="./$FILENAME"
    PARAMS="$VENDOR,$REGION,$TYPE,$TARGET_YEAR,$TARGET_MONTH"

    # Java Reporter 실행 및 출력 캡처
    CAPTURE=$(java -jar "$JAR_FILE" "p=$PROP_FILE" Finance.getReport "$PARAMS" 2>&1)
    EXIT_CODE=$?

    if [ $EXIT_CODE -eq 0 ]; then
        # 성공 시 다운로드된 파일을 목표 폴더로 이동
        mv "$EXPECTED_FILE_IN_CWD" "$DOWNLOAD_DIR/" 2>/dev/null
        echo "$(date): [성공] $VENDOR 보고서 다운로드 완료."
    elif echo "$CAPTURE" | grep -q "Error 213"; then
        echo "$(date): [알림] $VENDOR - 해당 기간 리포트 없음 (Error 213)."
    elif echo "$CAPTURE" | grep -q "Error 117"; then
        echo "$(date): [지연] $VENDOR - 리포트 생성 전임 (Error 117). 추후 재시도 필요."
        OVERALL_SUCCESS=1
    elif echo "$CAPTURE" | grep -q "Error 123" || echo "$CAPTURE" | grep -q "Error 124"; then
        echo "$(date): [치명적 오류] 토큰 만료 또는 인증 실패!"
        echo "$CAPTURE" | mail -s "Apple Reporter 오류: 토큰 확인 필요" "$ADMIN_EMAIL"
        OVERALL_SUCCESS=1
    else
        echo "$(date): [오류] 알 수 없는 에러 발생 (Exit Code: $EXIT_CODE)"
        echo "$CAPTURE"
        OVERALL_SUCCESS=1
    fi
    sleep 1
done

exit $OVERALL_SUCCESS
EOF

    sudo chmod +x "$BIN_DIR/download_financial.sh"
    fn_log_info "스크립트 생성 완료: $BIN_DIR/download_financial.sh"
}

# --- 9. (신규 추가) 수동 다운로드 스크립트 생성 ---
fn_create_manual_script() {
    fn_log_info "수동 다운로드 스크립트(download_financial_manual.sh)를 생성합니다..."
    
    # 스크립트 내용 작성
    sudo tee "$BIN_DIR/download_financial_manual.sh" > /dev/null << 'EOF'
#!/bin/bash
#
# download_financial_manual.sh
# 기능: 날짜(YYYY-MM)를 직접 입력받아 해당 월의 재무 보고서를 다운로드합니다.
#

BASE_DIR="/opt/apple_reporter/bin"
JAR_FILE="Reporter.jar"
PROP_FILE="Reporter.properties"
DOWNLOAD_DIR="/opt/apple_reporter/reports/financial"
VENDOR_CONF="/opt/apple_reporter/bin/vendor.conf"

# 벤더 설정 로드
if [ ! -f "$VENDOR_CONF" ]; then
    echo "[오류] 벤더 설정 파일($VENDOR_CONF)이 없습니다."
    exit 1
fi
source "$VENDOR_CONF"

# --- 사용자 입력 받기 ---
echo "============================================="
echo "   Apple Financial Report Manual Download    "
echo "============================================="
read -p ">> 다운로드할 연월을 입력하세요 (예: 2024-05): " TARGET_DATE

# 입력 형식 검증 (정규식: 숫자4개-숫자2개)
if [[ ! "$TARGET_DATE" =~ ^[0-9]{4}-[0-9]{2}$ ]]; then
    echo "[오류] 날짜 형식이 올바르지 않습니다. YYYY-MM 형식으로 입력해주세요."
    exit 1
fi

# 연도와 월 분리
G_YEAR=$(echo "$TARGET_DATE" | cut -d'-' -f1)
G_MONTH=$(echo "$TARGET_DATE" | cut -d'-' -f2)
# 문자열을 숫자로 변환 (10진수 강제 지정, 08/09 입력 시 8진수 오류 방지)
G_MONTH=$((10#$G_MONTH))

# --- Apple 회계 기준 변환 로직 ---
# Apple 회계연도는 전년도 10월부터 시작됩니다.
# (예: 2023년 10월 -> 2024 회계연도 1기)
if [ $G_MONTH -ge 10 ]; then
    FISCAL_YEAR=$((G_YEAR + 1))
    FISCAL_PERIOD=$((G_MONTH - 9))
else
    FISCAL_YEAR=$G_YEAR
    FISCAL_PERIOD=$((G_MONTH + 3))
fi

echo "---------------------------------------------"
echo " 입력 날짜 : $G_YEAR 년 $G_MONTH 월"
echo " 변환 결과 : $FISCAL_YEAR 회계연도 / $FISCAL_PERIOD 기(Period)"
echo "---------------------------------------------"

# 실행 디렉터리 이동
cd "$BASE_DIR" || { echo "오류: $BASE_DIR 이동 실패"; exit 1; }
REGION="ZZ"
TYPE="Financial"

# 벤더별 다운로드 실행
for VENDOR in $VENDORS; do
    echo ">> [Vendor: $VENDOR] 다운로드 시도 중..."
    
    FILENAME="${VENDOR}_${REGION}_${TYPE}_${FISCAL_YEAR}_${FISCAL_PERIOD}.gz"
    PARAMS="$VENDOR,$REGION,$TYPE,$FISCAL_YEAR,$FISCAL_PERIOD"

    # Java 명령어 실행
    CAPTURE=$(java -jar "$JAR_FILE" "p=$PROP_FILE" Finance.getReport "$PARAMS" 2>&1)
    
    # 결과 확인 (파일이 생성되었는지 확인)
    if [ -f "./$FILENAME" ]; then
        mv "./$FILENAME" "$DOWNLOAD_DIR/"
        echo "   [성공] 다운로드 완료: $DOWNLOAD_DIR/$FILENAME"
    else
        echo "   [실패 또는 없음] 메시지: $CAPTURE"
    fi
    echo ""
done

echo "작업이 완료되었습니다."
EOF

    # 실행 권한 부여
    sudo chmod +x "$BIN_DIR/download_financial_manual.sh"
    fn_log_info "수동 스크립트 생성 완료: $BIN_DIR/download_financial_manual.sh"
}

# --- 메인 실행 함수 ---
main() {
    fn_log_info "====== Apple Reporter 설치 스크립트 시작 ======"

    # sudo 권한 확인 및 캐싱
    if [ "$EUID" -ne 0 ]; then
        if command -v sudo >/dev/null; then
            fn_log_info "설치 권한(root) 획득을 위해 sudo 암호를 요청합니다..."
            if ! sudo -v; then
                fn_log_error "sudo 인증 실패. 스크립트를 종료합니다."
                exit 1
            fi
        else
            fn_log_error "'sudo'가 없습니다. root 계정으로 실행하거나 sudo를 설치하세요."
            exit 1
        fi
    fi

    # 단계별 실행
    fn_detect_os
    fn_check_java
    fn_check_utils
    fn_create_directories
    fn_get_reporter_files
    fn_configure_properties
    fn_get_vendor_ids
    fn_create_scripts
    fn_create_manual_script

    fn_log_info "=========================================="
    fn_log_info "설치 완료."
    fn_log_info "1. 자동 실행: $BIN_DIR/download_financial.sh (Crontab 등록용)"
    fn_log_info "2. 수동 실행: $BIN_DIR/download_financial_manual.sh (직접 실행용)"
    fn_log_warn "주의: 생성된 스크립트 내 'ADMIN_EMAIL'을 수정해주세요."
    fn_log_info "=========================================="
}

main
