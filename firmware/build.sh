#!/usr/bin/env bash
# ==================================================================
# 为 小米 MiWiFi Nano (xiaomi_miwifi-nano) 构建定制 OpenWrt 固件
#
# 流程：下载官方 ImageBuilder → 校验 sha256 → 渲染首次启动配置
#       → 按 packages.txt 增删软件包 → 打包生成 sysupgrade 固件
#
# 本脚本同时被 GitHub Actions 与本地环境使用。
# 本地运行需要能访问 downloads.openwrt.org 的 Linux x86_64 环境：
#
#     bash firmware/build.sh
#     WIFI_SSID=我的WiFi WIFI_KEY=mypassword123 bash firmware/build.sh
#
# 可选环境变量：
#   OPENWRT_VERSION  25.12.6（默认） | 24.10.8 | SNAPSHOT
#   WIFI_SSID        默认 MyNanoWiFi
#   WIFI_KEY         Wi-Fi 密码（>=8 位；留空 = 开放 WiFi，首次登录后再设）
#   ROOT_PASSWORD    root 密码（留空 = 首次登录 LuCI 时设置）
#
# 产物输出：out/<OPENWRT_VERSION>/*-sysupgrade.bin 与 sha256sums.txt
# ==================================================================
set -euo pipefail

OPENWRT_VERSION="${OPENWRT_VERSION:-25.12.6}"
TARGET="ramips/mt76x8"
PROFILE="xiaomi_miwifi-nano"
WIFI_SSID="${WIFI_SSID:-MyNanoWiFi}"
WIFI_KEY="${WIFI_KEY:-}"
ROOT_PASSWORD="${ROOT_PASSWORD:-}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
WORK_DIR="$SCRIPT_DIR/.work"
DL_DIR="$WORK_DIR/dl"
OVERLAY_DIR="$WORK_DIR/overlay"
OUT_DIR="$REPO_ROOT/out/${OPENWRT_VERSION}"

echo "==> 目标设备: $PROFILE ($TARGET)  版本: $OPENWRT_VERSION"

# ---------- 参数校验 ----------
if [ -z "$WIFI_SSID" ]; then
	echo "!! WIFI_SSID 不能为空"; exit 1
fi
if [ ${#WIFI_KEY} -gt 0 ] && [ ${#WIFI_KEY} -lt 8 ]; then
	echo "!! WIFI_KEY 至少 8 位（当前 ${#WIFI_KEY} 位）"; exit 1
fi
if [ -n "$WIFI_KEY" ]; then WIFI_ENCRYPTION="psk2"; else WIFI_ENCRYPTION="none"; fi

ROOT_HASH=""
if [ -n "$ROOT_PASSWORD" ]; then
	ROOT_HASH="$(openssl passwd -6 "$ROOT_PASSWORD")"
fi

# ---------- 定位并下载 ImageBuilder ----------
if [ "$OPENWRT_VERSION" = "SNAPSHOT" ]; then
	DIST_URL="https://downloads.openwrt.org/snapshots/targets/${TARGET}"
else
	DIST_URL="https://downloads.openwrt.org/releases/${OPENWRT_VERSION}/targets/${TARGET}"
fi

mkdir -p "$DL_DIR"
echo "==> 查询 ImageBuilder: $DIST_URL"
LISTING="$(curl -fsSL "$DIST_URL/")"
TARBALL="$(printf '%s' "$LISTING" | grep -oE 'openwrt-imagebuilder-[^"<> ]+\.tar\.(zst|xz|gz)' | sort -u | head -n 1)"
if [ -z "$TARBALL" ]; then
	echo "!! 未能在发布目录中找到 ImageBuilder 下载地址"; exit 1
fi
echo "==> 下载: $TARBALL"
curl -fsSL --retry 3 -o "$DL_DIR/$TARBALL" "$DIST_URL/$TARBALL"
curl -fsSL --retry 3 -o "$DL_DIR/sha256sums" "$DIST_URL/sha256sums"
# sha256sums 每行格式为 "<哈希> *<文件名>"，比对前需剥掉文件名前的星号
SHA_LINE="$(awk -v f="$TARBALL" '{n=$NF; sub(/^\*/, "", n); if (n == f) print}' "$DL_DIR/sha256sums")"
[ -n "$SHA_LINE" ] || { echo "!! sha256sums 中未找到 $TARBALL"; exit 1; }
( cd "$DL_DIR" && printf '%s\n' "$SHA_LINE" | sha256sum -c - )

# ---------- 解包 ----------
IB_NAME="$(printf '%s' "$TARBALL" | sed -E 's/\.tar\.(zst|xz|gz)$//')"
IB_DIR="$WORK_DIR/$IB_NAME"
if [ ! -d "$IB_DIR" ]; then
	tar -xf "$DL_DIR/$TARBALL" -C "$WORK_DIR"
fi

# ---------- 渲染首次启动配置（uci-defaults）到 overlay ----------
rm -rf "$OVERLAY_DIR"
mkdir -p "$OVERLAY_DIR"
export SRC_DIR="$SCRIPT_DIR/files.template" OVERLAY_DIR
export WIFI_SSID WIFI_KEY WIFI_ENCRYPTION ROOT_HASH
python3 - <<'PYEOF'
import os, pathlib, shutil, stat

src = pathlib.Path(os.environ["SRC_DIR"])
dst = pathlib.Path(os.environ["OVERLAY_DIR"])
values = {k: os.environ[k] for k in ("WIFI_SSID", "WIFI_KEY", "WIFI_ENCRYPTION", "ROOT_HASH")}

for f in sorted(src.rglob("*")):
    if f.is_dir():
        continue
    rel = f.relative_to(src)
    out = dst / rel
    out.parent.mkdir(parents=True, exist_ok=True)
    text = f.read_text()
    for k, v in values.items():
        text = text.replace("__%s__" % k, v)
    out.write_text(text)
    # 保留可执行权限（uci-defaults 习惯 755，虽然被 source 执行不强制要求）
    out.chmod(out.stat().st_mode | stat.S_IXUSR | stat.S_IXGRP)
print("==> overlay 渲染完成: %d 个文件" % sum(1 for _ in dst.rglob('*') if _.is_file()))
PYEOF

# ---------- 构建 ----------
EXTRA_PKGS="$(grep -vE '^[[:space:]]*(#|$)' "$SCRIPT_DIR/packages.txt" | tr '\n' ' ')"
echo "==> 软件包: $EXTRA_PKGS"
echo "==> 开始打包固件（ImageBuilder 只组装不编译，通常几分钟完成）..."
make -C "$IB_DIR" image PROFILE="$PROFILE" FILES="$OVERLAY_DIR" PACKAGES="$EXTRA_PKGS"

# ---------- 收集产物 ----------
BIN_DIR="$IB_DIR/bin/targets/$TARGET"
mkdir -p "$OUT_DIR"
if ! compgen -G "$BIN_DIR/*-${PROFILE}-squashfs-sysupgrade.bin" > /dev/null; then
	echo "!! 未找到 sysupgrade 镜像，ImageBuilder 输出如下："
	ls -la "$BIN_DIR" || true
	exit 1
fi
cp "$BIN_DIR"/*-"${PROFILE}"-squashfs-sysupgrade.bin "$OUT_DIR/"
cp "$BIN_DIR/"*.manifest "$OUT_DIR/" 2>/dev/null || true
( cd "$OUT_DIR" && sha256sum ./*-sysupgrade.bin > sha256sums.txt )

echo
echo "========== 构建完成 =========="
ls -la "$OUT_DIR"
echo
echo "刷机文件: $OUT_DIR/ 下的 *-sysupgrade.bin"
