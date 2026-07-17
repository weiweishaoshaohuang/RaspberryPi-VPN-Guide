<div align="center">

# 使用 Raspberry Pi 4 海外自建VPN

> 這裡**硬體**以**家用樹莓派 4** 作為出口節點
>
> (其實**不一定要侷限於樹梅派**,任何可以上網且有CPU的硬體都可以拿來跑,比方說家裡不用的舊電腦、MAC...)
>
> 部署目前對 GFW 隱蔽性最高的 **VLESS + REALITY** 翻牆代理，
> 並搭配 **Tailscale** Mesh VPN、SSH 金鑰加固、DuckDNS 動態域名的完整工程實踐紀錄。
> 
>
> **適合族群：**
> - 海外華人（在美、歐、澳等地有家用寬頻，想把家裡的出口 IP 作為私人節點）或是有海外VPS用戶
> - 有需要翻牆的用戶，且對「把流量交給陌生 VPS / 機場」感到不安
> - 想自建節點、擺脫商業機場的工程師與技術愛好者
> - 對家用網路安全架構、GFW 對抗技術有研究興趣的人

</div>

---

## 目錄

- [為什麼不用商業 VPN？](#為什麼不用商業-vpn)
- [整體架構拓撲](#整體架構拓撲)
- [準備清單](#準備清單)
- [架設步驟](#架設步驟)
  - [1. 燒錄 OS 至樹莓派](#1-燒錄-os-至樹莓派)
  - [2. 簡易版：Tailscale Mesh VPN 部署](#2-簡易版tailscale-mesh-vpn-部署)
  - [3. 進階版：Xray + REALITY 高隱蔽代理](#3-進階版xray--reality-高隱蔽代理)
- [安全加固](#安全加固)
  - [SSH 金鑰認證 + 關閉密碼登入](#ssh-金鑰認證--關閉密碼登入)
  - [路由器端口映射（外部 22222 → 內部 22）](#路由器端口映射外部-22222--內部-22)
  - [隱藏 X-UI 面板公網端口](#隱藏-x-ui-面板公網端口)
  - [DuckDNS 動態域名綁定](#duckdns-動態域名綁定)
- [自動化腳本](#自動化腳本)
- [客戶端使用指南](#客戶端使用指南)
- [附錄：名詞解釋](#附錄名詞解釋)
- [免責聲明](#免責聲明)

---

## 為什麼不用商業 VPN？

| 比較項目 | 商業 VPN / 機場 | 本方案（自建） |
|---|---|---|
| 隱私風險 | VPS 提供商可能紀錄或出售流量 | 流量只經過自家設備 |
| IP 被封風險 | 多人共用，IP 特徵值高，容易被 GFW 標記 | 家用住宅 IP，極低特徵值 |
| 成本 | 月費 $5–$30 USD，機場可能跑路 | 一次性硬體費用，電費極低 |
| 協議隱蔽性 | 多數使用較舊協議 | VLESS + REALITY（目前最難被識別）|
| 自主控制 | 完全依賴第三方 | 完全自主，隨時可調整配置 |

---

## 整體架構拓撲

```mermaid
flowchart TD
    Client(["💻 客戶端\nv2rayN / v2rayNG"])
    GFW(["🔥 GFW\n防火長城"])
    Router["🏠 家用路由器\nPort Forward"]
    Pi["🍓 Raspberry Pi 4\n3X-UI · Xray · SSH · Tailscale"]
    Internet(["🌍 自由網際網路"])
    Duck["DuckDNS\n動態域名服務"]

    Client -->|"① VLESS+REALITY :443\n偽裝成合法 HTTPS"| GFW
    GFW -->|"② 無法識別，放行"| Router
    Router -->|"③ :443 → Pi:443\nXray 解密後轉發"| Pi
    Pi -->|"④ 出口流量"| Internet

    Router -. ":22222 → Pi:22\nSSH 管理通道（金鑰驗證）" .-> Pi
    Pi -. "每 5 分鐘更新公網 IP" .-> Duck
    Duck -. "域名解析" .-> Router
```

**流量路徑一覽：**

| 用途 | 完整路徑 |
|---|---|
| 翻牆 | 客戶端 `①` → GFW 放行 `②` → 路由器 :443 `③` → Xray REALITY `④` → 目標網站 |
| 遠端管理 | SSH Client → 路由器 :22222 → Pi :22（金鑰驗證） |
| X-UI 面板 | SSH Tunnel 本地轉發，面板不對公網直接開放 |

---

## 準備清單

### 硬體

| 項目 | 規格 | 備註 |
|---|---|---|
| 主機 | Raspberry Pi 4（建議 4GB RAM） | 主要計算節點 |
| 儲存 | microSD 卡 32GB，Class 10 以上(至少要能給你的樹梅派用) | 系統碟 |
| 讀卡機 | microSD → USB / SD | 燒錄用，一次性使用 |
| 路由器 | 支援 Port Forwarding 的家用路由器 | 本文使用 ZyXEL PMG4506-T20B |
| 管理電腦 | Windows / macOS / Linux 皆可 | 燒錄與 SSH 管理 |

### 軟體 / 帳號

- [Raspberry Pi Imager](https://www.raspberrypi.com/software/) — OS 燒錄工具
- [Tailscale 帳號](https://tailscale.com/) — 免費方案即可
- [DuckDNS 帳號](https://www.duckdns.org/) — 免費動態 DNS

---

## 架設步驟

### 1. 燒錄 OS 至樹莓派

#### 1.1 下載並安裝 Raspberry Pi Imager

前往 [raspberrypi.com/software](https://www.raspberrypi.com/software/) 下載對應平台的版本。

#### 1.2 燒錄設定

啟動 Imager，插入 microSD 卡後依序選擇：

- **設備**：Raspberry Pi 4
- **OS**：Ubuntu Server 24.04.x LTS (64-bit)
- **儲存媒體**：你的 SD 卡

點擊齒輪圖示 ⚙ 展開進階設定：

| 設定項目 | 建議值 | 說明 |
|---|---|---|
| Hostname | `pi-vpn` | 區網內可直接用此名稱 ping 到，免查 IP |
| Username | `YOUR_USERNAME` | 避免使用預設 `pi`，降低自動攻擊命中率 |
| Password | 強密碼 | 後續會改為金鑰驗證，這是暫時用 |
| Enable SSH | ✅ | 遠端管理必開 |
| Wi-Fi（選填） | SSID / 密碼 | 有線網路更穩定，建議優先用網線 |

按 **Write** 開始燒錄，完成後插入樹莓派並接電開機。

![RPi Imager 燒錄設定畫面](docs/images/rpi_imager_flash.png)

#### 1.3 確認連通性

```bash
ping pi-vpn
```

![Ping 測試結果](docs/images/ping_test.png)

```bash
ssh YOUR_USERNAME@pi-vpn
```

![SSH 首次登入](docs/images/ssh_login.png)

#### 1.4 安裝基礎工具

```bash
sudo apt update && sudo apt upgrade -y
sudo apt install git vim curl wget -y
```

---

### 2. 簡易版：Tailscale Mesh VPN 部署

> **Tailscale** 是基於 WireGuard 的 Mesh VPN，支援 NAT Traversal 自動打洞，無需設定 Port Forwarding 即可讓設備跨網路互連。
>
> **限制**：WireGuard 特徵明顯，可能被 GFW 識別封鎖，適合作為管理通道而非主力翻牆使用。

#### 2.1 安裝 Tailscale

```bash
curl -fsSL https://tailscale.com/install.sh | sh
```

#### 2.2 加入你的虛擬網路

```bash
sudo tailscale up
# 終端會輸出一個登入 URL，用瀏覽器開啟並以 Google / GitHub 帳號登入即可
```

![Tailscale 管理後台](docs/images/tailscale_dashboard.png)

#### 2.3 開啟 IP 轉發（出口節點必要條件）

```bash
echo 'net.ipv4.ip_forward = 1' | sudo tee -a /etc/sysctl.conf
echo 'net.ipv6.conf.all.forwarding = 1' | sudo tee -a /etc/sysctl.conf
sudo sysctl -p
```

（選填）優化 UDP GRO 轉發效能：

```bash
sudo ethtool -K eth0 rx-udp-gro-forwarding on rx-gro-list off
```

#### 2.4 啟動為出口節點

```bash
sudo tailscale up --advertise-exit-node
```

進入 [Tailscale 管理後台](https://login.tailscale.com/admin/machines) → 找到 Pi → **Edit route settings** → 勾選 **Use as exit node**。

#### 2.5 驗證

```bash
# 在樹莓派上查詢公網 IP
curl https://api.ipify.org/
```

![樹莓派公網 IP](docs/images/pi_public_ip.png)

| 連接 Tailscale 前 | 連接 Tailscale 後 |
|:---:|:---:|
| ![連接前（行動數據 IP）](docs/images/mobile_ip_before_vpn.png) | ![連接後（台灣家用 IP）](docs/images/mobile_ip_after_vpn.png) |

#### 2.6 Tailscale 常用指令

```bash
tailscale status                               # 查看所有節點狀態
tailscale ping <裝置名或 Tailscale IP>         # 測試與節點的延遲
tailscale file cp <檔案路徑> <裝置名>:         # 免帳密直接傳檔（替代 scp）
sudo tailscale down                            # 斷開 VPN 隧道（服務程序保留）
sudo systemctl stop tailscaled                 # 完全停止 Tailscale 服務
sudo tailscale up --advertise-exit-node        # 重新啟用出口節點
sudo tailscale up --advertise-exit-node=false  # 關閉出口節點功能
```

> **注意**：Tailscale MagicDNS 預設沿用上次連接的 DNS 紀錄，區網與 Tailscale 環境切換時若 Hostname 解析失敗，改用 `100.x.x.x` IP 直接連線即可。

#### 2.7 Mesh 網路封包驗證（WireShark）

![WireShark 捕獲 Tailscale Mesh 封包](docs/images/wireshark_tailscale_mesh.png)

---

### 3. 進階版：Xray + REALITY 高隱蔽代理

> **選擇 REALITY 協議的核心原因：**
> - 不需要域名或 SSL 憑證，直接借用真實網站的合法 TLS 憑證
> - GFW 主動探測時，REALITY 將請求轉發至真實目標站，GFW 看到完全合法的 TLS 握手
> - 只有持有正確私鑰的客戶端才能建立加密通道
> - Xray 核心在 Raspberry Pi 4 上運行輕量穩定

#### 3.1 安裝 3X-UI 管理面板

```bash
sudo su
bash <(curl -Ls https://raw.githubusercontent.com/MHSanaei/3x-ui/master/install.sh)
```

官方倉庫：[MHSanaei/3x-ui](https://github.com/MHSanaei/3x-ui)

#### 3.2 路由器設定

**固定樹莓派內網 IP（Static DHCP）**

進入路由器管理後台 → 網路設定 → LAN Setting → Static DHCP，填入 MAC Address 與欲固定的 IP。

```bash
# 在樹莓派上查詢 MAC Address
ip link show eth0
```

**設定 Port Forwarding**

| 規則名稱 | 外部端口 | 內部 IP | 內部端口 | 協議 |
|---|---|---|---|---|
| Xray-REALITY | 443 | YOUR_PI_LOCAL_IP | 443 | TCP |
| SSH-管理通道 | 22222 | YOUR_PI_LOCAL_IP | 22 | TCP |

> 外部 22222 對應 Pi 內部 SSH 端口 22；使用非標準外部端口可大幅降低自動掃描攻擊頻率。

#### 3.3 在 X-UI 介面建立入站規則

瀏覽器前往：`http://YOUR_PI_LOCAL_IP:2053/YOUR_PANEL_PATH/`

左側選單 → **入站列表** → **新增入站**，填入：

| 欄位 | 值 |
|---|---|
| 協議 | vless |
| 端口 | 443 |
| 傳輸 | TCP |
| 安全 | Reality |
| uTLS | chrome（模擬 Chrome TLS 指紋）|
| Target | `www.yahoo.com:443` |
| SNI | `www.yahoo.com` |

點擊 **Get New Cert** 生成公私鑰對，再點擊 **建立**。

#### 3.4 客戶端安裝

**Android（v2rayNG）**

前往 [v2rayNG Releases](https://github.com/2dust/v2rayNG/releases)，下載 `arm64-v8a.apk`。掃描 X-UI 面板 QR Code 匯入節點。

> ⚠️ QR Code 可能預設含內網 IP，需手動修改為公網 IP 或 DuckDNS 域名。

**Windows（v2rayN）**

前往 [v2rayN Releases](https://github.com/2dust/v2rayN/releases) 下載並解壓縮，複製 `vless://` 連結匯入節點。

---

## 安全加固

### SSH 金鑰認證 + 關閉密碼登入

> 樹莓派一旦公網暴露，平均幾分鐘內就會出現自動化暴力破解攻擊。

**Step 1：在 Windows 客戶端生成 Ed25519 金鑰對**

```powershell
ssh-keygen -t ed25519 -C "my_windows_pc"
# 存於 C:\Users\YOUR_USERNAME\.ssh\
```

**Step 2：將公鑰上傳至樹莓派**

```powershell
type $env:USERPROFILE\.ssh\id_ed25519.pub | ssh YOUR_USERNAME@YOUR_PI_LOCAL_IP `
  "mkdir -p ~/.ssh && chmod 700 ~/.ssh && cat >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"
```

> ⚠️ Windows 終端偶爾在公鑰開頭插入 BOM 字元，導致驗證失敗，若登入異常請手動寫入 `authorized_keys`。

**Step 3：關閉密碼驗證**

```bash
# 直接執行自動化腳本（推薦）
sudo bash scripts/setup_security.sh
```

腳本會同時修正 Ubuntu 24.04 的 `/etc/ssh/sshd_config.d/*.conf` 覆蓋設定問題。

手動方式（兩個檔案都要改）：

```bash
sudo nano /etc/ssh/sshd_config
# PasswordAuthentication no
# PubkeyAuthentication yes

sudo nano /etc/ssh/sshd_config.d/50-cloud-init.conf
# PasswordAuthentication no

sudo systemctl restart ssh
```

**Step 4：驗證**

```bash
ssh -o PubkeyAuthentication=no YOUR_USERNAME@YOUR_PI_LOCAL_IP
# 預期：Permission denied (publickey).
```

---

### 路由器端口映射（外部 22222 → 內部 22）

| 設計意圖 | 說明 |
|---|---|
| 外部 `:22222` → 內部 `:22` | 掃描工具優先掃描 22 端口，非標準外部端口可大幅降低暴露面 |
| 外部 `:443` → 內部 `:443` | Xray REALITY 流量，對外偽裝為正常 HTTPS |

從外部連入：

```bash
# 直接 SSH
ssh -p 22222 YOUR_USERNAME@your-domain.duckdns.org

# SSH Tunnel 存取 X-UI 面板（面板不對公網開放）
ssh -p 22222 -L 2053:localhost:2053 YOUR_USERNAME@your-domain.duckdns.org
# 瀏覽器開啟 http://localhost:2053/YOUR_PANEL_PATH/
```

---

### 隱藏 X-UI 面板公網端口

路由器的 Port Forwarding **只開放 443 和 22222**，2053 不對公網開放。即使攻擊者掃描公網 IP 也找不到面板入口，只能透過 SSH Tunnel（需要金鑰）才能存取。

---

### DuckDNS 動態域名綁定

> 家用 ISP 公網 IP 是動態分配的，路由器重啟後 IP 可能改變。DuckDNS 讓固定域名自動追蹤當前 IP。

1. 前往 [duckdns.org](https://www.duckdns.org/) 登入，新增子域名並記下 **Token**
2. 在腳本頂部填入 Domain 和 Token，執行：

```bash
nano scripts/duckdns_sync.sh   # 填入 DUCKDNS_DOMAIN 和 DUCKDNS_TOKEN
bash scripts/duckdns_sync.sh
```

3. 驗證 DNS 解析與公網 IP 一致：

```bash
nslookup your-domain.duckdns.org
curl https://api.ipify.org/
```

此後所有連線都改用域名：

```bash
ssh -p 22222 YOUR_USERNAME@your-domain.duckdns.org
```

---

## 自動化腳本

| 腳本 | 功能 | 執行身分 |
|---|---|---|
| [`scripts/setup_security.sh`](scripts/setup_security.sh) | SSH 金鑰加固、關閉密碼登入、Ubuntu 24.04 雙設定檔修正 | sudo |
| [`scripts/duckdns_sync.sh`](scripts/duckdns_sync.sh) | 建立 DuckDNS 更新腳本並安裝 cron 任務 | 一般用戶 |

```bash
git clone https://github.com/YOUR_GITHUB_USERNAME/raspi-reality-homelab.git
cd raspi-reality-homelab

sudo bash scripts/setup_security.sh

nano scripts/duckdns_sync.sh   # 填入 Domain / Token
bash scripts/duckdns_sync.sh
```

---

## 客戶端使用指南

### v2rayN 介面說明（Windows）

![v2rayN 主介面](docs/images/v2rayn_interface.png)

#### 系統代理模式

| 模式 | 效果 | 使用場景 |
|---|---|---|
| 自動配置系統代理 | 接管 Windows 系統代理，瀏覽器自動跟隨 | **最常用**，日常翻牆 |
| 清除系統代理 | 關閉代理，恢復直連 | 下載大陸大檔案、測試原生網速 |
| 不改變系統代理 | 不干預系統代理設定 | 配合 SwitchyOmega 等擴充套件 |
| PAC 模式 | 透過 PAC 文件判斷哪些網址走代理 | 舊式方案，現已少用 |

#### 路由模式

| 模式 | 效果 | 使用場景 |
|---|---|---|
| 繞過大陸（Whitelist）| 大陸網站直連，境外網站走代理 | **在大陸時強烈推薦** |
| 全局（Global）| 所有流量走代理 | 確保所有請求來自台灣 IP |
| 黑名單（Blacklist）| 只有黑名單網址走代理 | 特殊場景 |

#### TUN 模式（整機代理）

建立虛擬網卡，強制接管整台電腦所有封包。**適用場景**：PowerShell / SSH 直連樹莓派、遊戲、Discord、Spotify 等不遵循系統代理的軟體需要翻牆。

#### 系統代理 vs TUN 模式的本質差異

| 比較項目 | 系統代理（HTTP Proxy） | TUN 模式（虛擬網卡） |
|---|---|---|
| 工作層級 | 應用層 L7 | 網路層 L3 |
| 覆蓋範圍 | 遵循系統代理設定的應用（主要是瀏覽器） | 整台電腦所有流量，無例外 |
| 協議支援 | HTTP / HTTPS / SOCKS5 | TCP + UDP + ICMP（全協議）|
| 無法覆蓋的場景 | curl、遊戲用戶端、部分 App | 幾乎沒有 |
| 效能損耗 | 低 | 略高 |

#### 日誌區常見訊息

```
accepted tcp:www.google.com:443 [socks -> proxy]   # ✅ 流量正常轉發
connection refused                                  # ❌ 家用 IP 可能已變，確認 DuckDNS 是否同步
timeout                                             # ❌ 443 被封，檢查 Port Forwarding
```

---

## 常見問題排除

### 問題一：TUN 模式出現 `context deadline exceeded`（路由迴圈）

**症狀**：開啟 TUN 模式後，v2rayN 日誌不斷出現 `context deadline exceeded`，網路完全斷開。

**根本原因**：

系統代理模式下，App 是「主動選擇」把請求丟給 v2ray 本地 port，v2ray 的出站流量不會被自己攔截，運作正常：

```
App 想連 Google
  ↓
App 把請求丟給 v2ray 本地 port（如 1080）
  ↓
v2ray 的 process 直接連到 YOUR_PI_PUBLIC_IP:443（走正常網卡）
  ↓
Pi → Google
```

TUN 模式則會接管整張路由表，導致 v2ray 的出站封包也被自己攔截，形成無限迴圈：

```
v2ray 想連 YOUR_PI_PUBLIC_IP:443
  ↓
封包進入 OS 網路層
  ↓
路由表：所有 IP 走 tun0（虛擬網卡）
  ↓
封包被 v2ray 自己讀到 → 「這要送去 YOUR_PI_PUBLIC_IP:443」→ 再送一次
  ↓
無限迴圈 → Context deadline exceeded
```

**解決方式**：在路由規則中為 VPN 伺服器加一條 `direct` 規則，讓 v2ray 的出站流量繞過 tun0：

v2rayN → **設定** → **路由規則設定** → 新增一條規則：

| 欄位 | 值 |
|---|---|
| 備註 | `bypass-vpn-server` |
| Domain | `your-domain.duckdns.org` |
| 出站 | `direct` |

儲存後重啟核心。加了此規則後：

```
v2ray 想連 your-domain.duckdns.org:443
  ↓
路由規則命中：direct → 走真實網卡，不進 tun0
  ↓
正常連線成功
```

---

### 問題二：未設定 `flow`，流量在 GFW 下特徵明顯

**症狀**：連線可用，但在大陸網路環境下容易被干擾或封鎖。

**根本原因**：

未設定 flow 時，連線 Google（HTTPS）的流量結構是 TLS 包著 TLS：

```
外層：VLESS + REALITY（TLS）
  └─ 內層：Google 的 HTTPS（也是 TLS）
```

正常瀏覽器不會產生雙層 TLS 結構，GFW 的深度包檢測從統計特徵就能識別這是代理流量。

`xtls-rprx-vision` 的解法是在 REALITY 握手完成後，直接將內層 TLS 原始封包「拼接」進去，消除雙層 TLS 特徵：

```
外層 REALITY 握手完成後
  ↓
內層 TLS 原始封包直接拼接（不再雙重封裝）
  ↓
GFW 看到的是：完整的 Yahoo TLS 握手 + 正常的 TLS 應用資料
  ↓
無法與真實 Yahoo 流量區分
```

**解決方式（Server 和 Client 必須同時設定）**：

#### Server 端（樹莓派）

直接用 sqlite3 更新資料庫設定，再重啟 x-ui：

```bash
sudo sqlite3 /etc/x-ui/x-ui.db \
  "UPDATE inbounds SET settings = json_set(settings, '$.clients[0].flow', 'xtls-rprx-vision') WHERE id = 1;"
sudo systemctl restart x-ui
```

#### Client 端

**手機（v2rayNG）**：長按伺服器設定 → 編輯 → 找到 **Flow** 欄位，填入 `xtls-rprx-vision` → 儲存

**電腦（v2rayN）**：伺服器列表雙擊編輯 → **流控** 欄位填入 `xtls-rprx-vision` → 儲存

#### 驗證是否生效

Flow 有個特性：Server 和 Client 必須同時設或同時不設，否則直接連不上。

1. Client 設好 `xtls-rprx-vision` 後，確認可以正常連線
2. 故意把 Client 的 flow 清空，測試連線
3. 清空後若連不上 → 代表 Server 確實在強制要求 flow，兩端均已生效

---

## 附錄：名詞解釋

### GFW 的識別手段

| 技術 | 說明 |
|---|---|
| IP 封鎖 | 直接封鎖已知 VPN 服務的 IP 段 |
| DNS 汙染 | 將被封鎖域名解析至錯誤 IP |
| 深度包檢測（DPI）| 分析封包特徵，識別代理協議流量 |
| 主動探測 | 向可疑 IP 發送探測請求，判斷是否為代理伺服器 |
| 大數據 + ML | 統計流量行為模式，識別與正常 HTTPS 的統計差異 |

### 協議演進與隱蔽性對比

```
Shadowsocks → VMess → Trojan → VLess → REALITY
              隱蔽性逐步提升 ────────────────────▶
```

| 協議 | 核心技術 | 對 GFW 的隱蔽性 |
|---|---|---|
| Shadowsocks | 輕量級 SOCKS5 代理 + 對稱加密 | ❌ 已可被 DPI 識別 |
| VMess | UUID 驗證 + 時間戳機制 | ⚠️ 特徵逐漸被識別 |
| Trojan | 完整模仿 HTTPS，在 443 監聽 | ⚠️ 部分環境下被識別 |
| VLESS | VMess 輕量化，解耦加密與傳輸 | ✅ 需搭配 REALITY |
| **REALITY** | 借用真實域名 TLS 憑證，無法與正常 HTTPS 區分 | ✅ **目前最高隱蔽性** |

### 系統代理 vs TUN 模式（原理）

**系統代理**：作業系統設定代理端口（如 `127.0.0.1:10809`），遵循此設定的應用程式將請求先發送給本地代理程式，再轉發至 VPN 節點。不遵循的程式（遊戲、curl、SSH）流量仍直連。

**TUN 模式**：在網路層建立虛擬網卡並修改路由表，讓所有封包強制進入虛擬網卡，任何應用程式、任何協議均無法繞過。

### 內核（Core）

| 內核 | 說明 |
|---|---|
| **Xray** | V2Ray 的高效能社群分支，支援 VLESS、VMess、Shadowsocks、Trojan、REALITY 等全協議 |
| sing-box | 新興統一代理平台，跨平台支援完善，生態持續成長中 |

<br/>

---

## 免責聲明

本倉庫內容僅為個人技術學習與隱私保護目的之工程實踐紀錄，供研究與參考使用。使用者須自行評估並遵守所在地區的相關法律法規，本人不對任何因使用本文內容而產生的法律責任負責。

---

<div align="center">

如果這個專案對你有幫助，歡迎點個 ⭐ Star！

有問題或改進建議，歡迎開 [Issue](../../issues) 討論。

</div>
