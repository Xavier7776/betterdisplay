#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
source_file="${PWD}/../Resources/DisplayProductID-2750"
if [[ "${1:-}" != --authorized-install ]]; then
    print '此工具为 OF27QT（4c23:2750）安装 HiDPI 模式覆盖。当前机器已有配置，无需运行。'
    print 'macOS 将请求管理员授权。已有文件会备份；完成后请自行重启。'
    /usr/bin/osascript - "$0" "$source_file" <<'APPLESCRIPT'
on run arguments
    set installer to item 1 of arguments
    set sourceFile to item 2 of arguments
    do shell script "/bin/zsh " & quoted form of installer & " --authorized-install " & quoted form of sourceFile with administrator privileges
end run
APPLESCRIPT
    exit 0
fi
[[ $EUID -eq 0 ]] || { print -u2 '需要管理员权限'; exit 1; }
source_file="$2"
/usr/bin/plutil -lint "$source_file"
[[ "$(/usr/bin/plutil -extract DisplayVendorID raw -o - "$source_file")" == 19491 ]]
[[ "$(/usr/bin/plutil -extract DisplayProductID raw -o - "$source_file")" == 10064 ]]
model_dir=/Library/Displays/Contents/Resources/Overrides/DisplayVendorID-4c23
destination="$model_dir/DisplayProductID-2750"
[[ ! -L "$model_dir" && ! -L "$destination" ]] || { print -u2 '拒绝覆盖符号链接'; exit 1; }
/bin/mkdir -p "$model_dir"
if [[ -f "$destination" ]]; then
    backup="$destination.minidisplay-backup-$(/bin/date +%Y%m%d-%H%M%S)-$$"
    /bin/cp -p "$destination" "$backup"
    print "已备份：$backup"
fi
staging=$(/usr/bin/mktemp "$model_dir/.minidisplay.XXXXXX")
trap '/bin/rm -f "$staging"' EXIT
/usr/bin/install -o root -g wheel -m 0644 "$source_file" "$staging"
/bin/mv -f "$staging" "$destination"
print '已安装。没有重启或重新初始化显示器。请自行重启后打开 MiniDisplay。'
