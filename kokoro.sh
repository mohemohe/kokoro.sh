#!/bin/bash
KokoroShVersion=2
KokoroRc="${HOME}/.kokororc"

#######################################
# ホーム直下の.kokororcを読む
# Globals:
#   KokoroRc: kokoro.shの設定ファイルの保存場所
# Arguments:
#   None
# Returns:
#   None
#######################################
function loadConfig() {
  if [[ -r "${KokoroRc}" ]]; then {
    source "${KokoroRc}"
    checkConfig
  } else {
    createConfig
  } fi
}

#######################################
# .kokororcに必要な変数が定義されているか確認する
# Globals:
#   ACCESS_TOKEN: kokoro.ioのアクセストークン
# Arguments:
#   None
# Returns:
#   None
#######################################
function checkConfig() {
  if [[ "${ACCESS_TOKEN}" == "" ]]; then {
    errorLog "'${KokoroRc}' の 'ACCESS_TOKEN' が空っぽだよ💢"
    exit 1
  } fi
}

#######################################
# ホーム直下に.kokororcを作成する
# Globals:
#   KokoroRc: kokoro.shの設定ファイルの保存場所
# Arguments:
#   None
# Returns:
#   None
#######################################
function createConfig() {
  cat << EOS >| "${KokoroRc}"
API_BASE_URL='https://kokoro.io/api'
ACCESS_TOKEN=''
EOS

  errorLog "'${KokoroRc}' にコンフィグファイルを作ったから 'ACCESS_TOKEN' にアクセストークンを入れてね♥"

  exit 1
}

#######################################
# 動作環境チェック
# Globals:
#   None
# Arguments:
#   None
# Returns:
#   0: 問題なし
#   1: なんかたりない
#######################################
function checkCommand() {
  local result=0
  local requireCommandList='
    basename
    cat
    sort
    curl
    jq
  '

  for command in ${requireCommandList}; do {
    type "${command}" &> /dev/null
    if [[ "$?" == "1" ]]; then {
      result=1
    } fi
  } done

  echo $result
}

#######################################
# チャンネルの情報を取得する
# Globals:
#   ACCESS_TOKEN: kokoro.ioのアクセストークン
# Arguments:
#   $1: チャンネル名
# Returns:
#   *: チャンネルのリスト または チャンネルID 
#######################################
function getChannelList() {
  local result=
  local channels=$(curl -X GET \
                        --header 'Accept: application/json' \
                        --header "X-Access-Token: ${ACCESS_TOKEN}" \
                        'https://kokoro.io/api/v1/memberships?archived=false' \
                     2>/dev/null)
  if [[ "${1}" == "" ]]; then {
    # チャンネルリストを出力
    local list=$(echo "${channels}" | jq -r ".[] | { id: .channel.id, name: .channel.channel_name} | .id, .name")
    result=$(echo "${list}" | while read id; read name; [ "$id$name" ]; do {
      echo "${id} ${name}"
    } done | sort -k 2,2)
    echo "${result}"
  } else {
    # チャンネルIDを出力
    result=$(echo "${channels}" | jq -r ".[] | select(.channel.channel_name == \"${1}\") | .channel.id")
    echo -e "${result}"
  } fi
}

#######################################
# 指定したチャンネルのメッセージを取得する
# Globals:
#   ACCESS_TOKEN: kokoro.ioのアクセストークン
# Arguments:
#   $1: チャンネルID
# Returns:
#   None
#######################################
function getChannelMessage() {
  local channelId="$(getChannelList "${1}")"
  local messages=$(curl -X GET \
                        --header 'Content-Type: application/x-www-form-urlencoded' \
                        --header 'Accept: application/json' \
                        --header "X-Access-Token: ${ACCESS_TOKEN}" \
                        "https://kokoro.io/api/v1/channels/${channelId}/messages" \
                     2> /dev/null)
  
  echo "${messages}" \
    | jq  -c "reverse | .[] | { display_name: .display_name, raw_content: .raw_content, published_at: .published_at}" \
    | while read -r json; do {
        displayName=$(echo "${json}" | jq  -r ".display_name")
        publishedAt=$(echo "${json}" | jq  -r ".published_at" | xargs -I_ date -ujf %FT%TZ "_" +%s | xargs -I_ date -r "_" +%Y/%m/%d.%H:%M:%S)
        rawContent=$(echo "${json}" | jq  -r ".raw_content")

echo -e "\033[0;32m${publishedAt}\033[0;m \033[0;33m${displayName}\033[0;m"
cat <<EOS

${rawContent}

EOS
        horizontalLine
      } done
}

#######################################
# 指定したチャンネルにメッセージを投稿する
# Globals:
#   ACCESS_TOKEN: kokoro.ioのアクセストークン
# Arguments:
#   $1: チャンネルID
#   $2: メッセージ
# Returns:
#   None
#######################################
function postChannelMessage() {
  local channelId="$(getChannelList "${1}")"
  local result=$(curl -X POST \
        --header 'Content-Type: application/x-www-form-urlencoded' \
        --header 'Accept: application/json' \
        --header "X-Access-Token: ${ACCESS_TOKEN}" \
        --data-urlencode "message=${2}" \
        "https://kokoro.io/api/v1/channels/${channelId}/messages" \
    2> /dev/null)

  if [[ "$?" != "0" ]]; then {
    errorLog メッセージ投稿に失敗しました
  } fi
  if [[ "$(echo "${result}" | jq -r '.message')" == "Server Error" ]]; then {
    errorLog メッセージ投稿に失敗しました
  } fi
}

#######################################
# 指定したチャンネルを作成する
# Globals:
#   ACCESS_TOKEN: kokoro.ioのアクセストークン
# Arguments:
#   $1: チャンネル名
#   $2: 概要
# Returns:
#   None
#######################################
function createPublicChannel() {
  local result=$(curl -X POST \
        --header 'Content-Type: application/x-www-form-urlencoded' \
        --header 'Accept: application/json' \
        --header "X-Access-Token: ${ACCESS_TOKEN}" \
        --data-urlencode "channel[channel_name]=${1}" \
        --data-urlencode "channel[description]=${2}" \
        "https://kokoro.io/api/v1/channels" \
    2> /dev/null)

  if [[ "$?" != "0" ]]; then {
    errorLog チャンネル作成に失敗しました
  } fi
  if [[ "$(echo "${result}" | jq -r '.message')" == "Server Error" ]]; then {
    errorLog チャンネル作成に失敗しました
  } fi
}

#######################################
# 画面幅いっぱいに罫線を引く
# Globals:
#   None
# Arguments:
#   None
# Returns:
#   None
#######################################
function horizontalLine() {
  for i in $(seq 1 $(tput cols)); do
    echo -n '─'
  done
}

#######################################
# 標準エラー出力にログを吐く
# Globals:
#   None
# Arguments:
#   $1: 吐き出す文字列
# Returns:
#   None
#######################################
function errorLog() {
  echo "$1" 1>&2
}

#######################################
# helpだす
# Globals:
#   None
# Arguments:
#   $1...$n 
# Returns:
#   None
#######################################
function man() {
  local me=$(basename "${0}")

  cat << EOS 1>&2
  ${me} get channel                       : チャンネルリスト取得
  ${me} get [name]                        : 指定チャンネルのメッセージを取得
  ${me} post channel [name] [description] : パブリックチャンネル作成
  ${me} post [name] [message]             : 指定チャンネルにメッセージを投稿
EOS
}

#######################################
# main関数
# Globals:
#   None
# Arguments:
#   $1...$n 
# Returns:
#   None
#######################################
function main() {
  local mode="${1}"
  local channel="${2}"
  local name="${3}"
  shift 2
  local message=

  if [ -p /dev/stdin ]; then {
    message=$(cat -)
  } else {
    message="$*"
  } fi

  if [[ "$(checkCommand)" == "1" ]]; then {
    errorLog "動作に必要なコマンドがないよ"
    exit 1
  } fi

  loadConfig

  case "${mode}" in 
    "get" ) {
      if [[ "${channel}" == "channel" ]]; then {
        getChannelList
      } else {
        getChannelMessage "${channel}"
      } fi
    } ;;

    "post" ) {
      if [[ "${channel}" == "channel" ]]; then {
        createPublicChannel "${name}" "${message}"
      } else {
        postChannelMessage "${channel}" "${message}"
      } fi
    } ;;

    * ) {
      man
      exit 1
    } ;;
  esac

  exit 0
}
main $*
