# R24D

<img src="../img/r24d.jpg" align=right width=30%></img>

R24D is a low cost 24Ghz mmWave radar with presence and movement detection.

Tested with:
- MicRadar R24DVD1 - [AliExpress]{https://s.click.aliexpress.com/e/_DEaKFRN)
- Seeedstudio MR24HPC1 - [SeeedStudio store](https://www.seeedstudio.com/24GHz-mmWave-Sensor-Human-Static-Presence-Module-Lite-p-5524.html)

Module uses 2.0 headers. I've purchased [2.0 Dupont cables (2x3P)](https://www.aliexpress.com/item/1005004327111557.html?aff_fcid=d990ff4f1a7a4e808378e32a40aecad3-1690136370877-04300-_DcwFFoX&tt=CPS_NORMAL&aff_fsk=_DcwFFoX&aff_platform=shareComponent-detail&sk=_DcwFFoX&aff_trace_key=d990ff4f1a7a4e808378e32a40aecad3-1690136370877-04300-_DcwFFoX&terminal_id=3f8c776975fd455ba956809c02d71a91&afSmartRedirect=y) to just plug into the radar module.

Set Serial Tx and Serial Rx pins in Tasmota to the pins connected to RX and TX pins on the module.

Driver supports all standard functions. Underlying Open protocol is not added and will probably be a separate driver file if it gets implemented.

Driver file is `r24d.be`.

## Commands

### RadarDelay

Set delay time for no presence state

| Parameter | Value | 
| :--- | --- | 
| `0` | None |
| `1` | 10s | 
| `2` | 30s | 
| `3` | 1min |
| `4` | 2min |
| `5` | 5min |
| `6` | 10min |
| `7` | 30min |
| `8` | 60min |

### RadarRestart

Restarts radar module.

### RadarSensitivity

Set detection distance for static state

| Parameter | Sensitivity | Detection Radius (m)
| :--- | --- | ---
| `1` | Level 1 | 2.5m
| `2` | Level 2 | 3m
| `3` | Level 3 | 4m

### RadarScene

Set predefined scene mode

| Parameter | Scene Mode | Detection Radius (m)
| :--- | --- | ---
| `1` | Living room | 4m - 4.5m
| `2` | Bedroom | 3.5m - 4m
| `3` | Bathroom | 2.5m - 3m
| `4` | Area detection | 3m - 3.5m