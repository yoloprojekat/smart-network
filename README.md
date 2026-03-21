# 🌐 Smart Network (Failover Hotspot)

**Smart Network** je inteligentni mrežni modul razvijen za obrazovnu platformu **Pametno Vozilo**. Ovaj modul je kreiran kao deo projekta za nacionalno takmičenje **Galaksija Kup 2026**.

Glavni cilj ovog rešenja je da obezbedi stopostotnu dostupnost vozila (Raspberry Pi 5) u mrežnom okruženju, bez obzira na dostupnost eksternih Wi-Fi mreža.

## 🚀 Ključne Karakteristike

* **Automatski Failover:** Ukoliko sistem ne pronađe nijednu poznatu (sačuvanu) Wi-Fi mrežu, automatski podiže sopstveni **WPA2 Hotspot**.
* **Samostalni Oporavak (Self-Healing):** Na svakih 120 sekundi sistem skenira okruženje. Čim se pojavi poznata mreža (npr. kućni ruter ili školski Wi-Fi), sistem gasi Hotspot i povezuje se kao klijent.
* **Dockerized Arhitektura:** Kompletna logika je spakovana u lagani Docker kontejner, što omogućava brzu instalaciju i izolaciju od ostatka sistema.
* **mDNS Pristup:** Bez obzira na to da li je vozilo u Hotspot ili Client režimu, uvek mu možete pristupiti preko hostname-a (npr. `http://pametno-vozilo.local`).
* **Optimizovano za Raspberry Pi 5:** Koristi `NetworkManager` putem D-Bus interfejsa, što je standard za najnoviji Raspberry Pi OS (Bookworm).

## 🛠️ Kako to funkcioniše?

Sistem koristi Python skriptu unutar Docker kontejnera koja komunicira sa host operativnim sistemom. Umesto da direktno upravlja Wi-Fi hardverom, kontejner šalje instrukcije **NetworkManager-u** na samom Raspberry Pi-ju.

1.  **Boot:** Sistem proverava da li postoji aktivna Wi-Fi veza.
2.  **Scan:** Ako nema veze, vrši se skeniranje dostupnih SSID-ova.
3.  **Fallback:** Ako nema poznatih mreža, pokreće se `SmartHotspot`.
4.  **Monitor:** Svaka 2 minuta se ponavlja provera kako bi se omogućio automatski povratak na primarnu mrežu.

## 📦 Instalacija

```
docker pull https://hub.docker.com/repository/docker/yoloprojekat/smart-network
```

<div align="center">

Autor: **Danilo Stoletović** 
**ETŠ „Nikola Tesla“ Niš • 2026**

</div>
