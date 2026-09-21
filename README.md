# 🌐 Smart Network (Failover Hotspot)

**Smart Network** je ultra-lagani, inteligentni mrežni modul razvijen za platformu **Pametno Vozilo** (optimizovan za **DietPi OS** i **Debian / Raspberry Pi OS**). Projekat je kreiran kao deo rešenja za nacionalno takmičenje **Galaksija Kup 2026**.

Glavni cilj ovog rešenja je da obezbedi stopostotnu dostupnost Raspberry Pi 5 uređaja u mreži: ukoliko vozilo nije povezano na poznatu Wi-Fi mrežu, automatski i trenutno se podiže lokalni **WPA2 Access Point (Hotspot)** sa omogućenim **SSH pristupom**. Čim poznata mreža postane dostupna u okruženju (a Hotspot nije u aktivnoj upotrebi), sistem se neprimetno vraća u klijentski režim.

---

## ⚡ Zašto smo uklonili Docker, Python i NetworkManager?

U ranijim verzijama projekta sistem je koristio Docker kontejner, Python skriptu i NetworkManager. Tokom testiranja na Raspberry Pi 5 uočeni su ozbiljni nedostaci:

* ⏱️ **Ubrzanje boot-a (uklonjeno kašnjenje od ~1 min):** Podizanje Docker daemona i pokretanje kontejnera produžavalo je vreme boot-a za **više od 1 minut**.
* 🪶 **Minimalna potrošnja resursa:** Docker kontejner i Python runtime trošili su preko 150 MB RAM-a i generisali nepotreban I/O. Prelaskom na čistu **Bash skriptu** i direktan rad sa **`wpasupplicant`**-om, potrošnja memorije svedena je na svega **~2 MB**.
* 🚀 **Neblokirajući i brz start (`systemd`):** Novi servis je podešen kao `Type=simple` unutar `systemd`-a. Servis se startuje asinhrono u pozadini pri svakom startovanju sistema, ne usporava boot proces i u roku od **5 sekundi** podiže Hotspot ukoliko nema poznatih mreža.

---

## 🚀 Ključne Karakteristike & Stabilnost

* **Brzi Failover (~5 sekundi):** Pri podizanju sistema vrši se kratka provera (5s). Ako vozilo nije povezano na sačuvanu mrežu, Hotspot se odmah aktivira.
* **Zaštita aktivnih konekcija (Rock-Solid):** Hotspot se **nikada ne prekida** dok god je klijent povezan (npr. otvoren SSH terminal ili web sesija). Reskeniranje se vrši isključivo kada nema povezanih klijenata.
* **Garantovan SSH Pristup:**
  * Skripta dodeljuje vozilu statičku IP adresu (`192.168.4.1/24`).
  * Pokreće namenski, nekonfliktni DHCP servis (`dnsmasq` sa `--port=0` i `--bind-dynamic`) koji dodeljuje IP adrese uređajima koji se povežu.
  * Automatski verifikuje i po potrebi startuje SSH servis (**Dropbear** na DietPi-ju ili **OpenSSH**).
* **Kompatibilnost sa DietPi OS:** Prilagođeno za DietPi paket `wpasupplicant`, `ifupdown` i Dropbear SSH.
* **WPA2 CCMP/AES standard:** Konfigurisano sa `proto RSN`, `pairwise CCMP` i `group CCMP` kako moderni telefoni (Android, iPhone) i laptopovi ne bi odbijali vezu.
* **Samostalni Oporavak (Self-Healing):** Kada je Hotspot u stanju mirovanja (nema povezanih klijenata), sistem u pozadini proverava da li se pojavila poznata Wi-Fi mreža i automatski se prebacuje na nju.

---

## 🛠️ Kako sistem funkcioniše?

```
               ┌────────────────────────┐
               │    Sistem se podiže    │
               │ (neblokirajući systemd) │
               └───────────┬────────────┘
                           ▼
               ┌────────────────────────┐
               │ Provera Wi-Fi statusa  │◄─────────────────────────┐
               │     (do 5 sekundi)     │                          │
               └───────────┬────────────┘                          │
              Povezan?     │ Nije povezan                          │
          ┌────────────────┴──────────────┐                        │
          ▼                               ▼                        │
   [Klijent Režim]             [Trenutno podizanje AP]             │
Sačuvana mreža aktivna           SSID: Pametno-Vozilo_AP           │
   (Vozilo na mreži)             IP: 192.168.4.1 (SSH aktivan)     │
          │                               │                        │
          │                               ▼                        │
          │                     ┌────────────────────┐             │
          │                     │ Povezan klijent?   │             │
          │                     │ (SSH sesija / mob) │             │
          │                     └─────────┬──────────┘             │
          │                       Da │    │ Ne (u mirovanju)       │
          │            Održi stabilan │    ▼                        │
          │            Hotspot vezu   │  Skeniraj za poznate mreže │
          │                          │    │                        │
          │                          │    │ Pronađena?             │
          │                          │    ├── Da ──► [Ugasi AP &   │
          │                          │    │         Poveži klijent]│
          │                          │    └── Ne ──► [Ostani u AP] │
          └───────────────────┬──────┴─────────────────────────────┘
                              │
                              ▼
                   Čekaj CHECK_INTERVAL (120s)
                              │
                              └────────────────────────────────────┘
```

---

## 📦 Instalacija

Preuzmite repozitorijum i pokrenite instalacionu skriptu sa root privilegijama:

```bash
git clone https://github.com/yoloprojekat/smart-network.git
cd smart-network
sudo bash install.sh
```

Skripta će automatski:
1. Instalirati neophodne pakete (`wpasupplicant`, `dnsmasq`, `wireless-tools`, `iw`, `rfkill`).
2. Osigurati prisustvo `ctrl_interface` u `/etc/wpa_supplicant/wpa_supplicant.conf`.
3. Osigurati da je SSH servis (`dropbear` ili `ssh`) omogućen i pokrenut.
4. Instalirati skriptu u `/opt/smart-network/smart-network.sh`.
5. Kreirati konfiguracioni fajl `/etc/default/smart-network`.
6. Instalirati `smart-network.service` u `/etc/systemd/system/`.
7. Učitati i odmah aktivirati servis (`systemctl enable --now smart-network.service`).

---

## 🔑 Povezivanje i SSH pristup

1. Kada vozilo nije na poznatoj Wi-Fi mreži, potražite Wi-Fi mrežu:
   * **SSID:** `Pametno-Vozilo_AP`
   * **Šifra:** `galaksija2026`
2. Vaš uređaj (laptop/telefon) će automatski dobiti IP adresu iz opsega `192.168.4.x`.
3. Povežite se preko SSH-a:
   ```bash
   ssh root@192.168.4.1
   # ili:
   ssh dietpi@192.168.4.1
   ```
   *(Podrazumevana šifra za `root` i `dietpi` na DietPi OS-u je `pi`)*

---

## ⚙️ Konfiguracija

Podešavanja se po želji menjaju u fajlu `/etc/default/smart-network`:

```bash
sudo nano /etc/default/smart-network
```

Primer konfiguracije:
```bash
# Naziv Hotspot mreže koju vozilo emituje
HOTSPOT_SSID="Pametno-Vozilo_AP"

# Šifra Hotspot mreže (minimalno 8 karaktera)
HOTSPOT_PASS="galaksija2026"

# Interval provere dostupnosti poznatih mreža u mirovanju (sekunde)
CHECK_INTERVAL=120

# Wi-Fi interfejs (podrazumevano wlan0)
WLAN_INTERFACE="wlan0"

# IP adresa vozila u Hotspot režimu
HOTSPOT_IP="192.168.4.1"
HOTSPOT_SUBNET="24"
```

Nakon izmene konfiguracije, primenite izmene restartom servisa:
```bash
sudo systemctl restart smart-network
```

---

## 📊 Praćenje rada i statusa

* **Status servisa:**
  ```bash
  sudo systemctl status smart-network
  ```
* **Praćenje logova uživo:**
  ```bash
  sudo journalctl -u smart-network -f
  ```
* **Status povezanih uređaja na Hotspot:**
  ```bash
  sudo iw dev wlan0 station dump
  ```

---

## 🗑️ Deinstalacija

Ukoliko želite da u potpunosti uklonite servis i instalirane fajlove:

```bash
sudo bash install.sh --uninstall
```

---

<div align="center">

Autor: **Danilo Stoletović**  
**ETŠ „Nikola Tesla“ Niš • 2026**

</div>
