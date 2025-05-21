#! /bin/bash

# Fonction : Vérifie si la commande existe
check_dep() {
    command -v "$1" >/dev/null 2>&1
}

# Fonction : Installe le paquet selon le gestionnaire
install_dep() {
    echo "[!] $DEPENDANCE n'est pas installé. Tentative d'installation..."

    if command -v apt >/dev/null 2>&1; then
        sudo apt install -y "$1"
    else
        echo "[✖] Aucun gestionnaire de paquets compatible trouvé (apt, dnf, yum)."
        exit 1
    fi
}

echo "[*] Création des dossiers pour les autorités de certification..."
# Initialisation des répertoires pour les CA
mkdir -p /etc/ssl/ca_racine/{certs,csr,newcerts,private}
mkdir -p /etc/ssl/ca_intermediaire/{certs,csr,newcerts,private}
mkdir -p /etc/ssl/ca_serveur/{certs,csr,newcerts,private}
touch /etc/ssl/ca_racine/index.txt
touch /etc/ssl/ca_intermediaire/index.txt
echo 1000 > /etc/ssl/ca_racine/serial
echo 1000 > /etc/ssl/ca_intermediaire/serial

echo "[*] Vérification et installation des dépendances nécessaires..."
# Installation des paquets nécessaires
for DEPENDANCE in openssl apache2; do
    if check_dep "$DEPENDANCE"; then
        echo "[-] $DEPENDANCE est déjà installé."
    else 
        install_dep "$DEPENDANCE"
    fi
done

## Création de l'autorité de certification racine
echo "[*] Configuration de l'autorité de certification racine..."
# Copie et renommage du fichier de configuration OpenSSL pour la CA racine
cp ./openssl_racine.cnf /etc/ssl/ca_racine/
mv /etc/ssl/ca_racine/openssl_racine.cnf /etc/ssl/ca_racine/openssl.cnf

echo "[*] Génération de la clé privée de la CA racine..."
# Création de la clé privée de la CA racine
openssl genrsa -aes256 -out /etc/ssl/ca_racine/private/ca.key.pem 4096
chmod 400 /etc/ssl/ca_racine/private/ca.key.pem

echo "[*] Création du certificat auto-signé de la CA racine..."
# Création du certificat auto-signé de la CA racine
openssl req -subj "/C=FR/ST=HATE-GARONNE/L=TOULOUSE/O=ESGI/OU=ESGI-TOULOUSE/CN=RootCA"\
        -key /etc/ssl/ca_racine/private/ca.key.pem \
        -new -x509 -days 7300 -sha256 -extensions v3_ca -out /etc/ssl/ca_racine/certs/ca.cert.pem 
chmod 444 /etc/ssl/ca_racine/certs/ca.cert.pem

## Création de l'autorité de certification intermédiaire
echo "[*] Configuration de l'autorité de certification intermédiaire..."
# Copie et renommage du fichier de configuration OpenSSL pour la CA intermédiaire
cp ./openssl_intermediaire.cnf /etc/ssl/ca_intermediaire/
mv /etc/ssl/ca_intermediaire/openssl_intermediaire.cnf /etc/ssl/ca_intermediaire/openssl.cnf

echo "[*] Génération de la clé privée de la CA intermédiaire..."
# Création de la clé privée de la CA intermédiaire
openssl genrsa -aes256 -out /etc/ssl/ca_intermediaire/private/intermediate.key.pem 4096
chmod 400 /etc/ssl/ca_intermediaire/private/intermediate.key.pem

echo "[*] Création de la CSR pour la CA intermédiaire..."
# Création de la CSR pour la CA intermédiaire
openssl req -subj "/C=FR/ST=HATE-GARONNE/L=TOULOUSE/O=ESGI/OU=ESGI-TOULOUSE/CN=IntermediateCA"\
        -new -sha256 \
        -key /etc/ssl/ca_intermediaire/private/intermediate.key.pem \
        -out /etc/ssl/ca_intermediaire/csr/intermediate.csr.pem

echo "[*] Signature du certificat intermédiaire par la CA racine..."
# Signature du certificat intermédiaire par la CA racine
openssl ca -config /etc/ssl/ca_racine/openssl.cnf -extensions v3_intermediate_ca -days 3650 -notext -md sha256 \
        -in /etc/ssl/ca_intermediaire/csr/intermediate.csr.pem \
        -out /etc/ssl/ca_intermediaire/certs/intermediate.cert.pem
chmod 444 /etc/ssl/ca_intermediaire/certs/intermediate.cert.pem

echo "[*] Création de la chaîne de certificats intermédiaire..."

## Création de l'autorité de certification serveur
echo "[*] Génération de la clé privée du serveur..."
# Création de la clé privée du serveur
openssl genrsa -out /etc/ssl/ca_serveur/private/server.key.pem 2048
chmod 400 /etc/ssl/ca_serveur/private/server.key.pem

echo "[*] Création de la CSR pour le serveur..."
# Création de la CSR pour le serveur
openssl req -subj "/C=FR/ST=HATE-GARONNE/L=TOULOUSE/O=ESGI/OU=ESGI-TOULOUSE/CN=Server" \
        -key /etc/ssl/ca_serveur/private/server.key.pem \
        -new -sha256 -out /etc/ssl/ca_serveur/csr/server.csr.pem

echo "[*] Signature du certificat serveur par la CA intermédiaire..."
# Signature du certificat serveur par la CA intermédiaire
openssl ca -config /etc/ssl/ca_intermediaire/openssl.cnf -extensions server_cert -days 750 -notext -md sha256 \
        -in /etc/ssl/ca_serveur/csr/server.csr.pem \
        -out /etc/ssl/ca_serveur/certs/server.cert.pem
chmod 444 /etc/ssl/ca_serveur/certs/server.cert.pem

echo "[*] Création de la chaîne complète de certificats pour le serveur..."
cat  /etc/ssl/ca_serveur/certs/server.cert.pem /etc/ssl/ca_intermediaire/certs/intermediate.cert.pem \
        /etc/ssl/ca_racine/certs/ca.cert.pem > /etc/ssl/ca_intermediaire/certs/ca-chain.cert.pem
chmod 444 /etc/ssl/ca_intermediaire/certs/ca-chain.cert.pem

echo "[*] Activation des modules SSL et rewrite pour Apache..."
sudo a2enmod ssl
sudo a2enmod rewrite

APACHE_SSL_DIR="/etc/apache2/ssl"
sudo mkdir -p $APACHE_SSL_DIR

echo "[*] Copie des certificats dans le dossier Apache SSL..."
sudo cp /etc/ssl/ca_serveur/certs/server.cert.pem $APACHE_SSL_DIR/server.cert.pem
sudo cp /etc/ssl/ca_intermediaire/certs/ca-chain.cert.pem $APACHE_SSL_DIR/ca-chain.cert.pem 
sudo cp /etc/ssl/ca_serveur/private/server.key.pem $APACHE_SSL_DIR/server.key.pem
sudo chmod 600 $APACHE_SSL_DIR/server.key.pem
sudo chmod 644 $APACHE_SSL_DIR/server.cert.pem $APACHE_SSL_DIR/ca-chain.cert.pem

APACHE_SSL_CONF="/etc/apache2/sites-available/default-ssl.conf"

echo "[*] Création du fichier de configuration Apache SSL..."
sudo tee $APACHE_SSL_CONF > /dev/null <<EOF
<VirtualHost *:443>
        ServerName localhost
        ServerAdmin webmaster@localhost
        DocumentRoot /var/www/html

        SSLEngine on
        SSLCertificateFile      $APACHE_SSL_DIR/server.cert.pem
        SSLCertificateChainFile $APACHE_SSL_DIR/ca-chain.cert.pem 
        SSLCertificateKeyFile   $APACHE_SSL_DIR/server.key.pem

        <Directory /var/www/html>
                Options Indexes FollowSymLinks
                AllowOverride All
                Require all granted
        </Directory>

        ErrorLog \${APACHE_LOG_DIR}/error.log
        CustomLog \${APACHE_LOG_DIR}/access.log combined
</VirtualHost>
EOF

echo "[*] Activation du site SSL dans Apache..."
sudo a2ensite default-ssl

echo "[*] Redémarrage du service Apache..."
sudo systemctl restart apache2

echo "[+] Apache SSL configuré et démarré sur https://localhost"
