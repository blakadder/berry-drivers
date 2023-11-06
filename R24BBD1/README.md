# Micradar R24BBD1 and Seeedstudio MR24BSD1

<img src="../img/r24b.jpg" align=right width=30%></img>

R24BBD1 is a 24Ghz mmWave radar with presence, movement, sleep, breathing and heart rate detection.

Tested with:
- MicRadar R24BBD1 - [AliExpress](https://www.aliexpress.com/item/1005005553211938.html?aff_fcid=f06534aa14ab40439056358b0ca38df6-1699309672380-01086-_DkvHD55&tt=CPS_NORMAL&aff_fsk=_DkvHD55&aff_platform=shareComponent-detail&sk=_DkvHD55&aff_trace_key=f06534aa14ab40439056358b0ca38df6-1699309672380-01086-_DkvHD55&terminal_id=f6d770ce532d41d9aee8c03b1a87a6b5&afSmartRedirect=y)
- Seeedstudio MR24BSD1 - [SeeedStudio store](https://www.seeedstudio.com/24GHz-mmWave-Radar-Sensor-Sleep-Breathing-Monitoring-Module-p-5304.html?sensecap_affiliate=jo7uUTK&referring_service=gh)

<details>
  <summary>Module uses 2.0 headers so you'll need [2.0mm to 2.54mm cables](https://www.aliexpress.com/item/32404830160.html?aff_fcid=bde844456ec84feca957bdb73f9e0b72-1698946372209-00940-_DnMZzwr&tt=CPS_NORMAL&aff_fsk=_DnMZzwr&aff_platform=shareComponent-detail&sk=_DnMZzwr&aff_trace_key=bde844456ec84feca957bdb73f9e0b72-1698946372209-00940-_DnMZzwr) to connect to the radar module. </summary>
 [Everything Presence Lite Kit](https://templates.blakadder.com/everything_presence_lite.html) has built in headers to easily use the sensor.  
 Another option are these [2 row header Dupont cables (2x3P)](https://www.aliexpress.com/item/1005004327111557.html?aff_fcid=d990ff4f1a7a4e808378e32a40aecad3-1690136370877-04300-_DcwFFoX&tt=CPS_NORMAL&aff_fsk=_DcwFFoX&aff_platform=shareComponent-detail&sk=_DcwFFoX&aff_trace_key=d990ff4f1a7a4e808378e32a40aecad3-1690136370877-04300-_DcwFFoX&terminal_id=3f8c776975fd455ba956809c02d71a91&afSmartRedirect=y) that can be soldered to the board.
</details>

Set Serial Tx and Serial Rx pins in Tasmota to the pins connected to RX and TX pins on the module.

| Micradar | ESP |
|---|---|
| Vcc |5V       |
| GND |GND      |
| RX  |Serial Tx  |
| TX  | Serial Rx | 

Driver supports all standard functions. My version with firmware G24VD1SYV010106 doesn't give any responses to commands so they're not completely implemented.

Load driver from autoexec.be with `load('r24bbd1.be')`.

## Commands

:warning: Not working on my firmware.

### RadarRestart

Sends restart command to the radar module.

### RadarSend

`function, addresscode1, addresscode2, data` is the expected format. Data is optional. There is zero error checking and if something is wrong it will fail silently

[Datasheet](datasheet/)