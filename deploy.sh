#!/bin/bash

# ==============================================================================
# Balaban Oto Servis - VPS Deployment Script (Docker Compose)
# ==============================================================================
# Bu betik, local bilgisayarınızdaki proje dosyalarını VPS sunucunuza aktarır,
# sunucuda Docker kurulu değilse kurar ve projeyi Docker Compose ile ayağa kaldırır.
# ==============================================================================

# Renk tanımlamaları
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0;7m' # No Color
CLEAR='\033[0m'

echo -e "${BLUE}=====================================================${CLEAR}"
echo -e "${BLUE}        BALABAN OTO SERVIS VPS DEPLOYMENT BETIGI     ${CLEAR}"
echo -e "${BLUE}=====================================================${CLEAR}"

# --- YAPILANDIRMA ---
# Sunucu bilgilerinizi buraya yazabilirsiniz veya betik çalışırken sorulacaktır.
VPS_IP=""         # Örn: "123.45.67.89"
VPS_USER="root"   # Genelde "root" veya "ubuntu" olur
VPS_PATH="/var/www/balabanotoservis"
SSH_KEY=""        # Örn: "~/.ssh/id_rsa" (Boş bırakılırsa şifre sorulur/varsayılan SSH kullanılır)

# Değişkenler boş ise kullanıcıdan girdi alalım
if [ -z "$VPS_IP" ]; then
    read -p "Sunucu IP adresini girin: " VPS_IP
fi

if [ -z "$VPS_IP" ]; then
    echo -e "${RED}[HATA] Sunucu IP adresi boş olamaz!${CLEAR}"
    exit 1
fi

read -p "Kullanıcı adı [$VPS_USER]: " input_user
VPS_USER=${input_user:-$VPS_USER}

read -p "Hedef dizin [$VPS_PATH]: " input_path
VPS_PATH=${input_path:-$VPS_PATH}

read -p "SSH Key Yolu (Boş bırakmak için Enter): " input_key
SSH_KEY=${input_key:-$SSH_KEY}

# SSH parametrelerini ayarla
SSH_OPTS=""
if [ -n "$SSH_KEY" ]; then
    SSH_OPTS="-i $SSH_KEY"
fi

echo -e "\n${YELLOW}=== [1/5] Sunucu Bağlantısı Test Ediliyor... ===${CLEAR}"
ssh $SSH_OPTS -o ConnectTimeout=10 "${VPS_USER}@${VPS_IP}" "echo 'Bağlantı başarılı!'" 2>/dev/null
if [ $? -ne 0 ]; then
    echo -e "${RED}[HATA] Sunucuya SSH ile bağlanılamadı! Lütfen IP adresinizi ve SSH anahtarınızı/şifrenizi kontrol edin.${CLEAR}"
    exit 1
fi
echo -e "${GREEN}Bağlantı doğrulandı.${CLEAR}"

echo -e "\n${YELLOW}=== [2/5] Sunucuda Docker ve Docker Compose Kontrolü Yapılıyor... ===${CLEAR}"
# Docker kurulu mu kontrol et
ssh $SSH_OPTS "${VPS_USER}@${VPS_IP}" "command -v docker >/dev/null 2>&1"
DOCKER_INSTALLED=$?

if [ $DOCKER_INSTALLED -ne 0 ]; then
    echo -e "${YELLOW}Docker sunucuda kurulu bulunamadı. Kurulmasını ister misiniz? (y/n)${CLEAR}"
    read -p "(Ubuntu/Debian için otomatik kurulum yapılacaktır): " install_docker
    if [[ "$install_docker" =~ ^[Yy]$ ]]; then
        echo -e "${BLUE}Docker kurulumu başlatılıyor... (Bu işlem birkaç dakika sürebilir)${CLEAR}"
        ssh $SSH_OPTS "${VPS_USER}@${VPS_IP}" "
            sudo apt-get update && \
            sudo apt-get install -y apt-transport-https ca-certificates curl software-properties-common && \
            curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor --yes -o /usr/share/keyrings/docker-archive-keyring.gpg && \
            echo 'deb [arch=\$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu \$(lsb_release -cs) stable' | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null && \
            sudo apt-get update && \
            sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin && \
            sudo systemctl enable docker && \
            sudo systemctl start docker
        "
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}Docker ve Docker Compose başarıyla kuruldu!${CLEAR}"
        else
            echo -e "${RED}[HATA] Docker kurulumu başarısız oldu. Lütfen manuel kurun.${CLEAR}"
            exit 1
        fi
    else
        echo -e "${RED}[HATA] Docker olmadan dağıtım yapılamaz. Kurulum iptal edildi.${CLEAR}"
        exit 1
    fi
else
    echo -e "${GREEN}Docker zaten kurulu.${CLEAR}"
fi

# Hedef dizini oluştur
ssh $SSH_OPTS "${VPS_USER}@${VPS_IP}" "sudo mkdir -p ${VPS_PATH} && sudo chown -R ${VPS_USER}:${VPS_USER} ${VPS_PATH}"

echo -e "\n${YELLOW}=== [3/5] Proje Dosyaları VPS'e Senkronize Ediliyor... ===${CLEAR}"
# rsync kullanarak gereksiz dosyaları (node_modules, .git, build klasörleri vs.) hariç tutarak gönderelim
rsync -avz --delete \
    --exclude="node_modules" \
    --exclude=".git" \
    --exclude="dist" \
    --exclude=".DS_Store" \
    --exclude="*.log" \
    --exclude="deploy.sh" \
    -e "ssh $SSH_OPTS" \
    ./ "${VPS_USER}@${VPS_IP}:${VPS_PATH}/"

if [ $? -eq 0 ]; then
    echo -e "${GREEN}Dosyalar başarıyla gönderildi.${CLEAR}"
else
    echo -e "${RED}[HATA] Dosya senkronizasyonu başarısız oldu! rsync kurulu olduğundan emin olun.${CLEAR}"
    exit 1
fi

echo -e "\n${YELLOW}=== [4/5] Docker Container'ları Yeniden Başlatılıyor (Build)... ===${CLEAR}"
ssh $SSH_OPTS "${VPS_USER}@${VPS_IP}" "
    cd ${VPS_PATH} && \
    sudo docker compose down --remove-orphans && \
    sudo docker compose up -d --build
"

if [ $? -eq 0 ]; then
    echo -e "${GREEN}Container'lar başarıyla başlatıldı ve güncellendi!${CLEAR}"
else
    echo -e "${RED}[HATA] Docker Compose build veya start aşamasında bir hata oluştu!${CLEAR}"
    exit 1
fi

echo -e "\n${YELLOW}=== [5/5] Uygulama Durumu Kontrol Ediliyor... ===${CLEAR}"
ssh $SSH_OPTS "${VPS_USER}@${VPS_IP}" "sudo docker ps"

echo -e "\n${GREEN}=====================================================${CLEAR}"
echo -e "${GREEN}   TEBRİKLER! DAĞITIM (DEPLOY) BAŞARIYLA TAMAMLANDI. ${CLEAR}"
echo -e "${GREEN}   Uygulamanıza tarayıcıdan erişebilirsiniz:          ${CLEAR}"
echo -e "${BLUE}   http://${VPS_IP}                                  ${CLEAR}"
echo -e "${GREEN}=====================================================${CLEAR}"
