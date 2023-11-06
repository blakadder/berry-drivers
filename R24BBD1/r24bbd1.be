#- v0.1
MicRadar R24BBD1 24Ghz sleep, breathing and presence radar
source from https://github.com/blakadder/berry-drivers
Tasmota driver written in Berry | code by blakadder released under GPL-3.0 license -#

import string
import mqtt
import json

var topic = tasmota.cmd('Status ', true)['Status']['Topic']

class micradar : Driver

  static sensorname = "R24BBD1"
  static buffer = {}
  static cfg_buffer = {}
  static header = 0x55
  static endframe = "5443"

  # tables of values and their names, edit to translate to another language

  static unk = "Unknown"      # value used when encountering Unknown data
  static wok = { 0x0F: "OK" } # when value is 0x0F replace with OK
  static wbool = { 0x00: false, 0x01: true }
  static wonoff = { 0x00: "Off", 0x01: "On" }

  static wactivity = {
    0x00FFFF: "Unoccupied",
    0x0100FF: "Static",
    0x010101: "Moving"
  }

  static wbedstatus = {
    0x00: "Unoccupied",
    0x01: "Occupied",
    0x02: "Off",
  }

  static wtrackactivity = {
    0x00: "Stationary",
    0x01: "Motion"  
  }

  static winitstatus = {
    0x00: "Complete",
    0x01: "Incomplete",
    0x0F: "Completed"
  }

  static woccupancy = {
    0x00: "Unoccupied",
    0x01: "Occupied"
  }

  static wproximity = {
    0x010101: "None",
    0x010102: "Approaching",
    0x010103: "Leaving",
    0x010104: "Traversing"
  }

  static wduration = { # duration from "presence" to "no presence", default is 30s
    0x00: "0s",
    0x01: "10s",
    0x02: "30s", # default setting
    0x03: "1min",
    0x04: "2min",
    0x05: "5min",
    0x06: "10min",
    0x07: "30min",
    0x08: "60min",
  }

  static wbreathing = {
    0x01: "Breathless",
    0x02: "None",
    0x03: "Normal",
    0x04: "Abnormal movement",
    0x05: "Shortness of breath",
  }

  static wsleepstatus = {
    0x00: "Awake",
    0x01: "Light sleep",
    0x02: "Deep sleep",
    0x03: "Off"
  }

  static wsceneset = {
    0x00: "Default",
    0x01: "Area detection",
    0x02: "Bathroom",
    0x03: "Bedroom",
    0x04: "Office",
    0x05: "Hotel",
  }

  # "props" is used to define strings for hex values when used
  # "config": true is a flag that tells the driver to write the value in config buffer instead of main buffer

  static rep = {
    0x04: {
      "name": "Active report",
      "a1": {
        0x01: { 
          "name": "Module", 
          "ignore": true , 
          "a2": {
            0x01: { "name": "Device ID" },
            0x02: { "name": "Software version" },
            0x03: { "name": "Hardware version" },
            0x04: { "name": "Protocol version" },
                }
              },
        0x03: { 
          "name": "Radar",
          "a2": {
            0x05: { "name": "Activity", "props": micradar.wactivity },
            0x06: { "name": "Body movement" },
            0x07: { "name": "Target", "props": micradar.wproximity }
                }
              },
        0x05: { 
          "name": "Info",
          "a2": {
            0x01: { "name": "Heartbeat", "props": micradar.wactivity },
            0x02: { "name": "Abnormal reset", "props": micradar.wok, "ignore": true },
            0x09: { "name": "Feedback OTA", "ignore": true },
            0x0A: { "name": "Initialisation", "props": micradar.wok, "ignore": true }
                }
              }
            }
          },
    0x05: {
      "name": "Sleep report",
      "a1": {
        0x01: { 
          "name": "Breathing",
          "a2": {
            0x01: { "name": "Respiratory rate" },
            0x04: { "name": "State", "props": micradar.wbreathing }
                }
              },
        0x03: { 
          "name": "Sleeping",
          "a2": {
            0x07: { "name": "Bed occupancy", "props": micradar.wbedstatus },
            0x08: { "name": "Sleep State", "props": micradar.wsleepstatus }
                }
              },
        0x04: { 
          "name": "Duration",
          "a2": {
            0x00: { "name": "Awake" },
            0x01: { "name": "Light sleep" },
            0x02: { "name": "Deep sleep" },
            0x03: { "name": "Not in datasheet" },
                }
              },
        0x05: { 
          "name": "Sleep quality",
          "a2": {
            0x01: { "name": "Score" },
                }
              },
        0x06: { 
          "name": "Heart rate",
          "a2": {
            0x01: { "name": "Value" },
                }
              },
            },
          },
    0x06: {
      "name": "0x06",
      "a1": {
        0x01: { 
          "name": "06/01",
          "a2": {
           0x01: { "name": "01" },
                }
              },
            },
          },
          }

  static cfg = {
    0x03: {
      "name": "Passive report",
      "a1": {
        0x01: { 
          "name": "Module",
          "a2": {
            0x01: { "name": "Device ID" },
            0x02: { "name": "Software version" },
            0x03: { "name": "Hardware version" },
            0x04: { "name": "Protocol version" },
                }
              },
        0x04: { 
          "name": "System parameters",
          "a2": {
            0x10: { "name": "Scene setting", "props": micradar.wsceneset },
            0x12: { "name": "Unnocupied delay", "props": micradar.wduration },
            0x0C: { "name": "Sensitivity" },
                }
              },
        0x05: { 
          "name": "Other",
          "a2": {
            0x04: { "name": "Restart", "props": micradar.wok, "ignore": true },
            0x08: { "name": "Start OTA upgrade", "props": micradar.wok, "ignore": true },
            0x09: { "name": "Upgrade package transfer", "ignore": true },
            0x10: { "name": "Respiratory monitoring", "props": micradar.wonoff },
            0x0A: { "name": "Upgrade end message", "ignore": true },
            0x0B: { "name": "0x0B" },
            0x0C: { "name": "0x0C" },
            0x0D: { "name": "Sleep monitoring", "props": micradar.wonoff },
            0x0E: { "name": "0x0E" },
                }
              },
            },
          },
        }
 
  var ser  # create serial port object

  # intialize the serial port, if unspecified Tx/Rx are GPIO 1/3
  def init(tx, rx)
    if !tx   tx = gpio.pin(gpio.TXD) end
    if !rx   rx = gpio.pin(gpio.RXD) end
    self.ser = serial(rx, tx, 9600, serial.SERIAL_8N1)
    tasmota.add_driver(self)
    end

  def write2buffer(l, target)
    # target.insert(l.find("name"),l.find("props") != nil ? l["props"][0x00] : 0)
    target.insert(l.find("name"),l.find("props") != nil ? "" : 0)
  end

  # populate buffer and ctl_buffer with control words from word table and default values (0x00)
  def buffer_init()
  # init config buffer
    var cf = self.cfg[0x03]["a1"]
    for k : cf.keys()
      self.cfg_buffer.insert(cf[k].find("name"),{})
      for l : cf[k]["a2"]
        if l.find("ignore") != true     
          self.write2buffer(l, self.cfg_buffer[cf[k]["name"]])
        end
      end
    end
    for k : self.rep.keys()
      for l : self.rep[k]["a1"].keys()
        if self.rep[k]["a1"][l].find("ignore") != true    
          self.buffer.insert(self.rep[k]["a1"][l].find("name"),{})
        else
          continue
        end
          for m : self.rep[k]["a1"][l]["a2"]
          if m.find("ignore") != true     
            self.write2buffer(m, self.buffer[self.rep[k]["a1"][l]["name"]])
          end
        end
      end 
    end
  end  

  # def restart()
  #   self.ser.write(self.encode("03", "05", "04", ""))
  #   print("Reset command sent")
  #   # tasmota.set_timer(3000, /-> self.get_config())
  # end
      
  def split_payload(b)
    var ret = []
    var s = size(b)   
    var i = s-2   # start from last-1
    while i > 0
      if b[i] == 0x55            
        ret.insert(0, b[i..s-1]) # push last msg to list
        b = b[(0..i-1)]   # write the rest back to b
      end
      i -= 1
    end
    ret.insert(0, b)
    return ret
  end

  def calculate_checksum(data, poly)
    if !poly  poly = 0xA001 end
    var crc = 0xFFFF
    for i:0..size(data)-1
      crc = crc ^ data[i]
      for j:0..7
        if crc & 1
          crc = (crc >> 1) ^ poly
        else
          crc = crc >> 1
        end
      end
    end
    return crc
  end

  def encode(fn, a1, a2, data)
    var d = bytes().fromhex(data) # store payload to calc msg size
    b = bytes('55') # add header
    b.add(size(d)+7,2)
    b += bytes(fn) # add function code
    b += bytes(a1) # add address code 1
    b += bytes(a2) # add address code 2
    b += d # add payload
    var chksum = self.calculate_checksum(b)
    b.add(chksum, -2) # add crc
    return b
  end

  def pub2log(result, lvl)
    log(f"MicR: {result}", lvl == nil ? 3 : lvl)
  end

  # send a command, format: function,address code 1, address code 2,data (or leave empty as "")
  def send(fn, a1, a2, data)
    var logr
    if !data   data = ""   end
    if size(fn) != 2 && size(a1) != 2 && size(a2) != 2
      logr = f"Parameters are wrong size!!! Must be in format: 00,00,00"
    else
    var payload_bin = self.encode(str(fn), str(a1), str(a2), str(data))
    self.ser.flush()
    tasmota.delay(10)
    self.ser.flush()
    self.ser.write(payload_bin)
    # print("MicR: Sent =", str(payload_bin))
    logr = f"command {payload_bin} sent"
    end
    self.pub2log(logr, 3)
  end

  # identify data and its type from self.rep and self.cfg maps
  def id_data(msg)
    var fn    = self.id_fn(msg)
    var prop  = fn[msg[3]]["a1"][msg[4]]["a2"][msg[5]].find("props")
    var s     = msg.get(1,2)-7
    var data
    if s > 4
      data = msg[6..-3].asstring()      
    # special handling for body movement since its 4bit float
    elif s == 4 && msg[4] == 0x03 && msg[5] == 0x06
      data = msg.getfloat(6)
    else
      data = msg.get(6,-s)
    end  
    return prop != nil ? prop.find(data) : data
  end

    # identify which map to use to collect field names
  def id_fn(msg)
    return msg[3] == 0x03 ? self.cfg : self.rep 
  end

  def parse_message(msg)
    var fn      = self.id_fn(msg)
    var a1      = fn[msg[3]]["a1"][msg[4]].find("name", self.unk)
    var a2      = fn[msg[3]]["a1"][msg[4]]["a2"][msg[5]].find("name", self.unk)
    var data    = self.id_data(msg)
    var result  = {}
    var ra1   = {}
    var ra2   = {}
    ra2.insert(a2,data)
    result.insert(a1,ra2)
    # print("Parsed message:", json.dump(result))
    # check if it exists in config
    var buf = msg[3] == 0x03 ? self.cfg_buffer : self.buffer
    if buf.find(a1) != nil 
      if buf[a1].find(a2) != nil 
        if buf[a1].find(a2) != data
        buf[a1].setitem(a2,data)
        # print(f"Buffer update {a1}: {a2} with {data}")  
        var pubtopic = "tele/" + topic + "/SENSOR"
        var mp = f"{{\"{self.sensorname}\":{json.dump(result)}}}"
        mqtt.publish(pubtopic, mp, false)
        end
      end
    else
      self.pub2log(f"{self.sensorname}: {a1} {a2} {data}", 2)
    end  
  end

  # read serial port
  def every_100ms()
    if self.ser.available() > 0
    var msg = self.ser.read()   # read bytes from serial as bytes
      if size(msg) > 0
        if msg[0] == self.header
          # print("MicR: msg =", msg)
          var lst = self.split_payload(msg)
          for i:0..size(lst)-1
            msg = lst[i]
            print("MicR: msg =", msg)
            if msg[3] == 0x05 || msg[3] == 0x04 || msg[3] == 0x06 # Active and passive report
              self.parse_message(msg)  
            elif msg[3] == 0x02 || msg[3] == 0x03 # Config
              self.parse_message(msg)  
            else
              print("Unknown message =", msg)
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
    msg.push(f"{{s}}<hr>{{m}}<hr>{{e}}")
    msg.push(f"{{s}}<i><b>{self.sensorname}{{m}} {{e}}")
    for k : self.buffer.keys()
      for l : self.buffer[k].keys()
        msg.push(f"{{s}}{l}{{m}}{self.buffer[k][l]}{{e}}")
      end
    end
    msg.push(f"</table><hr/>{{t}}{{s}}<i>Configuration{{m}}{{e}}")
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
  if size(data) < 4 data.push("") end
  radar.send(data[0], data[1], data[2], data[3])
  tasmota.resp_cmnd_done()
end

tasmota.add_cmd('RadarSend', radar_send)

def restart_cmnd(cmd, idx, payload, payload_json)
  radar.restart()
  tasmota.resp_cmnd_done()
end

tasmota.add_cmd('RadarRestart', restart_cmnd)

# tasmota.add_rule("system#boot", /-> radar.restart() ) # set rule to restart radar on system boot in order to populate sensors

