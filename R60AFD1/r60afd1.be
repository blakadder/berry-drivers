#-----------------------------------------
v0.01
60Ghz mmWave fall radar Tasmota driver  written in Berry | code by blakadder
Works with: Seeedstudio MR60FDA1, MicRadar R60AFD1
source from https://github.com/blakadder/berry-drivers
released under GPL-3.0 license
-#

import string
import mqtt
import json

var topic = tasmota.cmd('Status ', true)['Status']['Topic']

class micradar : Driver

  static sensorname = "R60AFD1"
  static buffer = {}
  static cfg_buffer = {}
  static header = bytes("5359")
  static endframe = "5443"

  # tables of values and their names, edit to translate to another language

  static unk = "Unknown"      # value used when encountering Unknown data
  static wok = { 0x0F: "OK" } # when value is 0x0F replace with OK

  static wactivity = {
    0x00: "None",
    0x01: "Still",
    0x02: "Active"
  }

  static winitstatus = {
    0x00: "Complete",
    0x01: "Incomplete",
    0x0F: "Completed"
  }

  static wfailurereport = {
    0x00: "None",
    0x01: "Radar chip error",
    0x02: "Encryption error"
  }

  static wfall = {
    0x00: "None",
    0x01: "Fallen"
  }

  static woccupancy = {
    0x00: "Unoccupied",
    0x01: "Occupied"
  }

  static wprotocolmode = {
    0x00: "Standard",
    0x01: "Advanced",
  }

  static wbool = {
    0x00: false,
    0x01: true
  }

  static wonoff = {
    0x00: "Off",
    0x01: "On"
  }

  # "properties" is used to define strings for hex values when used
  # "config": true is a flag that tells the driver to write the value in config buffer instead of main buffer

  static word = {
    0x01: {
      "name": "System",
      "word": {
        0x01: { "name": "Heartbeat", "properties": micradar.wok },
        0x02: { "name": "Reset", "properties": micradar.wok }
              }
          },
    0x02: {
      "name": "Information",
      "word": {
        0xA1: { "name": "Product Model" },
        0xA2: { "name": "Product ID" },
        0xA3: { "name": "Hardware Model" },
        0xA4: { "name": "Firmware Version" },
        0x04: { "name": "Firmware Version" }
              }
          },
    0x05: {
      "name": "Information",
      "word": {
        0x01: { "name": "Initialization",
                "properties": micradar.winitstatus },
        0x02: { "name": "Radar Failure",
                "properties": micradar.wfailurereport },
        0x03: { "name": "Working Hours" },
        0x07: { "name": "Scenario" },
              }
            },
    0x06: {
      "name": "Radar Installation",
      "word": {
        0x01: { "name": "Installation angle setting" },
        0x02: { "name": "Installation height setting" },
        0x03: { "name": "Automatic height measurement" }
              }
          },
    0x80: {
      "name": "Human",
      "word": {
        0x00: { "name": "Presence monitoring",
                "properties": micradar.wonoff,
                "config": true },
        0x01: { "name": "Presence",
                "properties": micradar.woccupancy },
        0x02: { "name": "Activity",
                "properties": micradar.wactivity },
        0x03: { "name": "Body Movement" },
        0x0D: { "name": "Stationary horizontal distance",
                "config": true },
        0x0E: { "name": "Moving horizontal distance",
                "config": true },
        0x12: { "name": "Non-presence time setting",
                "config": true },
            }
          },
    0x83: {
      "name": "Fall Detection",
      "word": {
        0x00: { "name": "Fall monitoring",
                "properties": micradar.wonoff,
                "config": true },
        0x01: { "name": "State",
                "properties": micradar.wfall },
        0x05: { "name": "Still state",
                "properties": micradar.wbool },
        0x0A: { "name": "Still time setting",
                "config": true },
        0x0B: { "name": "Still monitoring",
                "properties": micradar.wonoff,
                "config": true },
        0x0D: { "name": "Fall detection sensitivity",
                "config": true },
        0x0C: { "name": "Fall duration setting",
                "config": true },
        0x0E: { "name": "Height proportion report" },
        0x0F: { "name": "Height accumulation time",
                "config": true },
        0x11: { "name": "Fall breaking height setting",
                "config": true },
        0x12: { "name": "Trajectory point"},
        0x13: { "name": "Trajectory report frequency",
                "config": true },
        0x15: { "name": "Trajectory point monitoring",
                "properties": micradar.wonoff,
                "config": true },
              }
            }
        }
    
  var ser  # create serial port object

  # intialize the serial port, if unspecified Tx/Rx are GPIO 1/3
  def init(tx, rx)
    if !tx   tx = gpio.pin(gpio.TXD) end
    if !rx   rx = gpio.pin(gpio.RXD) end
    self.ser = serial(rx, tx, 115200, serial.SERIAL_8N1)
    tasmota.add_driver(self)
    end

  def write2buffer(l, target)
    target.insert(l.find("name"),l.find("properties") != nil ? l["properties"][0x00] : 0)
  end

  # populate buffer and ctl_buffer with control words from word table and default values (0x00)
  def buffer_init()
    for k : self.word.keys()
      if k == 0x05 || k == 0x06
      self.cfg_buffer.insert(self.word[k].find("name"),{})
        for l : self.word[k]["word"]
          self.write2buffer(l, self.cfg_buffer[self.word[k]["name"]])
        end
      end
    end
    for k : self.word.keys()
      if k > 127
        self.buffer.insert(self.word[k].find("name"),{})
        for l : self.word[k]["word"]
          if l.find("config") != nil
            self.write2buffer(l, self.cfg_buffer[self.word[0x05]["name"]])            
          else
            self.write2buffer(l, self.buffer[self.word[k]["name"]])
         end
        end
      end 
    end
  end  

  def restart()
    self.ser.write(self.encode("01", "02", "0F"))
    print("Reset command sent")
    tasmota.set_timer(3000, /-> self.get_config())
  end
    
  def publish2log(result, lvl)
    log(f"MicR: {result}", lvl == nil ? 3 : lvl)
  end
  
  def split_payload(b)
    var ret = {}
    var s = size(b)   
    var i = s-2   # start from last-1
    while i > 0
      if b[i] == 0x53 && b[i+1] == 0x59 && b[i-2] == 0x54 && b[i-1] == 0x43            
        ret.insert(0, b[i..s-1]) # push last msg to list
        b = b[(0..i-1)]   # write the rest back to b
      end
      i -= 1
    end
    ret.insert(0, b)
    return ret
  end

  def calculate_checksum(payload)
      var checksum = 0x00
      for i:0..size(payload)-1
          checksum = checksum + payload[i]
          checksum &= 0xFF  # Ensure the checksum stays within 8 bits
      end
      return checksum
  end
    
  def encode(ctrlword, cmndword, data)
    var d = bytes().fromhex(data) # store payload to calc msg size
    b = self.header # add header
    b += bytes(ctrlword) # add control word
    b += bytes(cmndword) # add command word
    b.add(size(d),-2)
    b += d # add payload
    var chksum = self.calculate_checksum(b)
    b.add(chksum, 1) # add crc
    b += bytes(self.endframe) # add frame end sequence
    return b
  end

  # send a command, format: controlword,commandword,data (if no data "0F" is used)
  def send(ctrlword, cmndword, data)
    var logr
    if !data   data = "0F"   end
    if size(ctrlword) != 2 && size(cmndword) != 2 && size(data) != 2
      logr = f"Parameters are wrong size!!! Must be in format: 00,00,00"
    else
    var payload_bin = self.encode(str(ctrlword), str(cmndword), str(data))
    self.ser.flush()
    self.ser.write(payload_bin)
    # print("MicR: Sent =", str(payload_bin))
    logr = f"command payload {payload_bin} sent"
    end
    self.publish2log(logr, 3)
  end

  # identify data and its type from micradar.word table
  def id_data(msg)
    var prop = self.word[msg[2]]["word"][msg[3]].find("properties")
    var data = msg[6]
    var result = prop != nil ? prop.find(data) : data  
    return result
  end

  # identify name from micradar.word table, return Unknown if it doesnt exist
  def id_name(msg)
    var field = self.word[msg[2]]["word"][msg[3]].find("name", self.unk)
    return field
  end

  # identify command word from micradar.word table, return Unknown if it doesnt exist
  def id_cw(msg)
    var field = self.word[msg[2]].find("name", self.unk)
    return field
  end

# grab options so the configuration buffer gets updated, triggered on init done message  
  def get_config()
    self.send("80","80","0F")
    self.send("83","8A","0F")
    self.send("83","8B","0F")
    self.send("83","8C","0F")
    self.send("83","8D","0F")
    self.send("83","8F","0F")
  end

  def get_version()
    self.send("02","A1","0F")
    self.send("02","A2","0F")
    self.send("02","A3","0F")
    self.send("02","A4","0F")
    self.send("04","04","0F")
  end

  def parse_productinfo(msg)
    var field = self.id_name(msg)
    var data  = msg[6..5+msg[5]].asstring()
    var result = f"{field}: {data}"
    self.publish2log(result, 2)
  end

  def parse_message(msg)
    var field   = self.id_name(msg)
    var data    = self.id_data(msg)
    var cw      = self.id_cw(msg)
    var result  = {}
    var val     = {}
    val.insert(field,data)
    result.insert(cw,val)
    # print("Parsed message:", result)
    # check if word exists in buffer then update the value if needed, won't publish anything if the value doesn't change
    if self.buffer.find(cw) != nil 
      if self.buffer[cw].find(field) != data
        self.buffer[cw].setitem(field,data)
        # print(f"Buffer update {field} with {data}")  
        var pubtopic = "tele/" + topic + "/SENSOR"
        var mp = f"{{\"{self.sensorname}\":{json.dump(result)}}}"
        mqtt.publish(pubtopic, mp, false)
      end
    else
      self.publish2log(f"{field}: {data}", 2)
    end  
  end

  def parse_config(msg)
    var field   = self.id_name(msg)
    var data    = self.id_data(msg)
    var cw      = self.word[0x05]["name"]
    var result  = {}
      result.insert(field,data)
    # print("Parsed message:", result)
    # check if word exists in buffer then update the value if needed, won't publish anything if the value doesn't change
    if self.cfg_buffer.find(cw) != nil 
      if self.cfg_buffer[cw].find(field)
        self.cfg_buffer[cw].setitem(field,data)
        # print(f"Config Buffer update {field} with {data}")  
        var pubtopic = "stat/" + topic + "/CONFIG"
        var mp = f"{{\"{self.sensorname}\":{json.dump(result)}}}"
        mqtt.publish(pubtopic, mp, false)
      end
    else
      self.publish2log(f"{field}: {data}", 2)
    end  
  end

  # read serial port
  def every_50ms()
    if self.ser.available() > 0
    var msg = self.ser.read()   # read bytes from serial as bytes
    import string
      if size(msg) > 0
        if msg[0..1] == self.header
          var lst = self.split_payload(msg)
          for i:0..size(lst)-1
            msg = lst[i]
            # print("MicR: msg =", msg)
            if msg[2] == 0x02 # Product Information
              self.parse_productinfo(msg)  
            else
              # if query command word is found change the bit to report as command word for easier parsing 
              var cmndword = msg.get(3,1) 
              if cmndword >= 128   
                msg.set(3,(cmndword - 128),1)  
              end 
              #  print("MicR: msg =", msg)
              if msg[2] == 0x05 || msg[2] == 0x06 || self.word[msg[2]]['word'][msg[3]].find("config")
                self.parse_config(msg)
                if msg[3] == 0x01
                  self.get_config()
                end
              else
              # print("MicR: msg =", msg)
                self.parse_message(msg)
              end
            end
          end
        end  
      end
    end
  end
  
  def json_append()
	  var msg = f",\"{self.sensorname}\":{json.dump(self.buffer)}"
    tasmota.response_append(msg)
  end

  def web_sensor()
    if !self.ser return nil end  #- exit if not initialized -#
    var msg = []
    for k : self.buffer.keys()
      for l : self.buffer[k].keys()
        msg.push(f"{{s}}{l}{{m}}{self.buffer[k][l]}{{e}}")
      end
    end
    msg.push(f"{{s}}<i>Configuration Status{{m}}<HR>{{e}}")
    # add configs to message
    for k : self.cfg_buffer.keys()
      for l : self.cfg_buffer[k].keys()
        msg.push(f"{{s}}{l}{{m}}{self.cfg_buffer[k][l]}{{e}}")
      end
    end
  tasmota.web_send(msg.concat())
  end
end

radar=micradar()
tasmota.add_driver(radar)
radar.buffer_init()

#- 
Add commands to use in Tasmota
-#

def radar_send(cmd, idx, payload, payload_json)
  var data = string.split(payload, ",")
  if size(data) < 3 data.push("0F") end
  radar.send(data[0], data[1], data[2])
  tasmota.resp_cmnd_done()
end

tasmota.add_cmd('RadarSend', radar_send)

def restart_cmnd(cmd, idx, payload, payload_json)
  radar.restart()
  tasmota.resp_cmnd_done()
end

tasmota.add_cmd('RadarRestart', restart_cmnd)

def switch_presence(cmd, idx, payload, payload_json)
  var ctl = "80"
  var cmw = "00"
  var val = "0F"
  if payload == "1" || payload == "ON" || payload == "off"
    val = "01"
  elif payload == "0" || payload == "OFF" || payload == "off"
    val = "00"
  else
    cmw = "80"
    log("MicRadat: Use 1/ON to turn on and 0/OFF to turn off. No payload shows current configuration")
  end
  radar.send(ctl,cmw,val)
  tasmota.resp_cmnd_done()
end

tasmota.add_cmd('RadarPresence', switch_presence)

def switch_fall(cmd, idx, payload, payload_json)
  var ctl = "83"
  var cmw = "00"
  var val = "0F"
  if payload == "1" || payload == "ON" || payload == "off"
    val = "01"
  elif payload == "0" || payload == "OFF" || payload == "off"
    val = "00"
  else
    cmw = "80"
    log("MicRadat: Use 1/ON to turn on and 0/OFF to turn off. No payload shows current configuration")
  end
  radar.send(ctl,cmw,val)
  tasmota.resp_cmnd_done()
end

tasmota.add_cmd('RadarFall', switch_fall)

def switch_residence(cmd, idx, payload, payload_json)
  var ctl = "83"
  var cmw = "0B"
  var val = "0F"
  if payload == "1" || payload == "ON" || payload == "off"
    val = "01"
  elif payload == "0" || payload == "OFF" || payload == "off"
    val = "00"
  else
    cmw = "8B"
    log("MicRadat: Use 1/ON to turn on and 0/OFF to turn off. No payload shows current configuration")
  end
  radar.send(ctl,cmw,val)
  tasmota.resp_cmnd_done()
end

tasmota.add_cmd('RadarResidence', switch_residence)

def set_sensitivity(cmd, idx, payload, payload_json)
  var opt = [1,2,3]
  var ctl = "83"
  var cmw = "0D"
  var val = "0F"
  if opt.find(int(payload)) != nil
    val = f"{payload:.2i}"
  else
    cmw = "8D"
    log("MicR: Set fall detection sensitivity. Accepted value range is 0 - 3. No payload shows current configuration")
  end
  radar.send(ctl,cmw,val)
  tasmota.resp_cmnd_done()
end

tasmota.add_cmd('SetSensitivity', set_sensitivity)

def set_falltime(cmd, idx, payload, payload_json)
  var ctl = "83"
  var cmw = "0C"
  var val = "0F"
  if int(payload) > 4 || int(payload) < 181
    val = f"{payload:.2i}"
  else
    cmw = "8C"
    log("MicR: Set fall time in seconds. Accepted value range is 5 - 180. No payload shows current configuration")
  end
  radar.send(ctl,cmw,val)
  tasmota.resp_cmnd_done()
end

tasmota.add_cmd('SetFalltime', set_falltime)

def set_residencetime(cmd, idx, payload, payload_json)
  var ctl = "83"
  var cmw = "0A"
  var val = "0F"
  if int(payload) > 59 || int(payload) < 3601
    val = f"{payload:.2i}"
  else
    cmw = "8A"
    log("MicR: Set fall time in seconds. Accepted value range is 5 - 180. No payload shows current configuration")
  end
  radar.send(ctl,cmw,val)
  tasmota.resp_cmnd_done()
end

tasmota.add_cmd('SetResidencetime', set_residencetime)

def set_hacctime(cmd, idx, payload, payload_json)
  var ctl = "83"
  var cmw = "0F"
  var val = "0F"
  if int(payload) >= 0 || int(payload) < 301
    val = f"{payload:.2i}"
  else
    cmw = "8F"
    log("MicR: Set fall time in seconds. Accepted value range is 5 - 180. No payload shows current configuration")
  end
  radar.send(ctl,cmw,val)
  tasmota.resp_cmnd_done()
end

tasmota.add_cmd('SetResidencetime', set_residencetime)

tasmota.add_rule("system#boot", /-> radar.restart() ) # set rule to restart radar on system boot in order to populate sensors
radar.get_version()