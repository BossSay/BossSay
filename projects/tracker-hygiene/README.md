# qBittorrent Tracker Hygiene Pipeline

A fully automated, evidence‑based 3‑stage pipeline for identifying, classifying, and removing dead or undesirable trackers from qBittorrent.

This system is built for operational reliability, reproducibility, and long‑term maintainability.

---

## 🔧 Pipeline Overview

### **1. Harvester**
Collects real announce‑cycle evidence from qBittorrent’s API and writes a structured dataset of tracker behavior.

Script: harvester/qbt-tracker-harvester-v2.2.1.ps1

### **2. Builder**
Processes harvested evidence and generates two blocklists:

- **domains.txt** — domain‑level blocks  
- **urls.txt** — full announce URL blocks  

Script: builder/qbt-build-blocklist-v2.2.1.ps1

### **3. Purge Engine**
Connects to qBittorrent and removes any tracker whose domain or URL matches the generated blocklists.

Script: purge/qbt-purge-blocklist-v1.1.5-s-logic.ps1

---

## 📁 Folder Structure

```
tracker-hygiene/
│
├── harvester/
│   └── qbt-tracker-harvester-v2.2.1.ps1
│
├── builder/
│   └── qbt-build-blocklist-v2.2.1.ps1
│
├── purge/
│   └── qbt-purge-blocklist-v1.1.5-s-logic.ps1
│
└── README.md
```


---

## 🧩 How It Works (Short Version)

1. **Run the Harvester**  
   Produces a JSON/CSV dataset of tracker behavior.

2. **Run the Builder**  
   Generates `domains.txt` and `urls.txt` based on real evidence.

3. **Run the Purge Engine**  
   Removes matching trackers from all torrents via qBittorrent’s API.

Better to wait until qBittorrent fully loaded — if qBittorrent is still hydrating its torrent list on startup, the /torrents/info call may return an incomplete set and some torrents will be missed. Give it a minute or two after launch before running the purge.

---

## 🎯 Purpose

This project exists to solve a long‑standing problem in the BitTorrent ecosystem:

- bloated tracker lists  
- dead/abandoned trackers  
- poisoned or malicious trackers  
- unnecessary announce storms  
- wasted bandwidth  
- slow swarm performance  

This pipeline keeps qBittorrent clean, fast, and operationally healthy.

---

## 📌 Status

Actively maintained.  
Designed for DevOps‑grade reproducibility and long‑term use.
