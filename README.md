# 🌐 Smart Network (Failover Hotspot)

**Smart Network** je ultra-lagani, inteligentni mrežni modul razvijen za obrazovnu platformu **Pametno Vozilo**. Projekat je kreiran kao deo rešenja za nacionalno takmičenje **Galaksija Kup 2026**.

Glavni cilj ovog rešenja je da obezbedi stopostotnu dostupnost Raspberry Pi 5 uređaja u mreži: ukoliko vozilo nije povezano na poznatu Wi-Fi mrežu, automatski se podiže lokalni **WPA2 Access Point (Hotspot)**, a čim poznata mreža postane dostupna, sistem se neprimetno vraća u klijentski režim.

---

## ⚡ Zašto smo uklonili Docker, Python i NetworkManager?

U ranijim verzijama projekta sistem je koristio Docker kontejner, Python skriptu i NetworkManager. Tokom testiranja na Raspberry Pi 5 uočeni su ozbiljni nedostaci:

* ⏱️ **Ubrzanje boot-a (uklonjeno kašnjenje od ~1 min):** Podizanje Docker daemona i pokretanje kontejnera na Raspberry Pi OS-u produžavalo je vreme boot-a za **više od 1 minut**.
* 🪶 **Minimalna potrošnja resursa:** Docker kontejner i Python runtime trošili su preko 150 MB RAM-a i generisali nepotreban I/O. Prelaskom na čistu **Bash skriptu** i direktan rad sa **`wpa_supplicant`**-om, potrošnja memorije svedena je na svega **~2 MB**.
* 🚀 **Neblokirajući boot (`systemd`):** Novi servis je podešen kao `Type=simple` unutar `systemd`-a. To znači da se servis pokreće asinhrono u pozadini pri svakom startovanju sistema i **uopšte ne usporava niti blokira boot proces**.

---

## 🚀 Ključne Karakteristike

* **Automatski Failover:** Ukoliko vozilo ne uspe da se poveže na sačuvane Wi-Fi mreže, automatski aktivira sopstveni **WPA2 Hotspot**.
* **Samostalni Oporavak (Self-Healing):** Na svakih 120 sekundi (podesivo) sistem vrši reskeniranje. Čim detektuje poznatu mrežu (npr. kućni ili školski ruter), gasi Hotspot i povezuje se kao klijent.
* **Čist Bash + `wpa_supplicant`:** Koristi standardni Linux bežični stek bez teških apstrakcija i posrednika.
* **On-Demand DHCP Server:** Za klijente koji se povezuju na vozilo (telefon, računar), lagani `dnsmasq` se automatski aktivira samo dok je Hotspot uključen i dodeljuje im IP adrese.
* **Jednostavna instalacija jednim potezom:** Skripta `install.sh` automatski podešava sve zavisnosti, postavlja skriptu i odmah osposobljava i pokreće `systemd` servis.

---

## 🛠️ Kako sistem funkcioniše?

```
               ┌────────────────────────┐
               │    Sistem se podiže    │
               │ (neblokirajući systemd) │
               └───────────┬────────────┘
                           ▼
               ┌────────────────────────┐
               │ Provera Wi-Fi statusa  │◄─────────────────┐
               │   (wpa_cli status)     │                  │
               └───────────┬────────────┘                  │
              Povezan?     │ Nije povezan                  │
          ┌────────────────┴──────────────┐                │
          ▼                               ▼                │
   [Klijent Režim]             [Reskeniranje mreža]        │
Sačuvana mreža aktivna        Čeka se 15 sekundi           │
   (Vozilo na mreži)                      │                │
          │                     Povezan?  │                │
          │                   ┌───────────┴──────────┐     │
          │               Da  ▼                   Ne ▼     │
          │        [Klijent Režim]          [Aktiviraj AP] │
          │                                  SmartHotspot  │
          │                                  + DHCP server │
          │                                          │     │
          └───────────────────┬──────────────────────┘     │
                              │                            │
                              ▼                            │
                   Čekaj CHECK_INTERVAL (120s)             │
                              │                            │
                              └────────────────────────────┘
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
1. Proveriti i po potrebi instalirati neophodne pakete (`wpa_supplicant`, `dnsmasq`, `wireless-tools`, `iproute2`).
2. Instalirati skriptu u `/opt/smart-network/smart-network.sh`.
3. Kreirati konfiguracioni fajl `/etc/default/smart-network`.
4. Instalirati `smart-network.service` u `/etc/systemd/system/`.
5. Učitati i odmah aktivirati servis (`systemctl enable --now smart-network.service`).

---

## ⚙️ Konfiguracija

Podešavanja se menjaju u fajlu `/etc/default/smart-network` bez potrebe za menjanjem samog koda skripte:

```bash
sudo nano /etc/default/smart-network
```

Primer konfiguracije:
```bash
# Naziv Hotspot mreže koju vozilo emituje
HOTSPOT_SSID="Pametno-Vozilo_AP"

# Šifra Hotspot mreže (minimalno 8 karaktera)
HOTSPOT_PASS="galaksija2026"

# Interval provere dostupnosti poznatih mreža (u sekundama)
CHECK_INTERVAL=120

# Wi-Fi interfejs (podrazumevano wlan0)
WLAN_INTERFACE="wlan0"

# IP adresa vozila u Hotspot režimu
HOTSPOT_IP="192.168.4.1"
HOTSPOT_SUBNET="24"
```

Nakon izmene konfiguracije, samo restartujte servis:
```bash
sudo systemctl restart smart-network
```

---

## 📊 Praćenje rada i statusa

* **Status servisa:**
  ```bash
  sudo systemctl status smart-network
  ```
* **Praćenje logova u realnom vremenu:**
  ```bash
  sudo journalctl -u smart-network -f
  ```
* **Zaustavljanje / Pokretanje:**
  ```bash
  sudo systemctl stop smart-network
  sudo systemctl start smart-network
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
