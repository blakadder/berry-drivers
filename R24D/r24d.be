#-----------------------------------------
24Ghz mmWave radar Tasmota driver v1.0 written in Berry | code by blakadder
Works with: Seeedstudio MR24HPC1, MicRadar R24DVD1
source from https://github.com/blakadder/berry-drivers
released under GPL-3.0 license
-#

import string
import mqtt
import json

var topic = tasmota.cmd('Status ', true)['Status']['Topic']

class micradar : Driver

  static sensorname = "R24DVD1"
  static buffer = {}
  static cfg_buffer = {}
  static op_buffer = {}
  static header = bytes("5359")
  static endframe = "5443"
  static opbool

  # tables of values and their names, edit to translate to another language

  static unk = "Unknown"      # value used when encountering Unknown data
  static wok = { 0x0F: "OK" } # when value is 0x0F replace with OK

  static wactivity = {
    0x00: "None",
    0x01: "Still",
    0x02: "Active"
  }

  static wduration = { # duration from "presence" to "no presence", default is 30s
    0x00: "0s",
    0x01: "10s",
    0x02: "30s", # default setting
    0x03: "1m",
    0x04: "2m",
    0x05: "5m",
    0x06: "10m",
    0x07: "30m",
    0x08: "60m",
  }

  static winitstatus = {
    0x00: "Complete",
    0x01: "Incomplete",
    0x0F: "Completed",
  }

  static wmovement = {
    0x00: "None",
    0x01: "Approaching",
    0x02: "Leaving"
  }

  static woccupancy = {
    0x00: "Unoccupied",
    0x01: "Occupied"
  }

  static wscenemode = {
    0x00: "Not Set",
    0x01: "Living Room",
    0x02: "Bedroom",
    0x03: "Bathroom",
    0x04: "Area Detection"
  }
  static wsensitivity = {
    0x00: "None",
    0x01: "2m",
    0x02: "3m",
    0x03: "4m" # default setting
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
        0xA5: { "name": "Protocol Type",
                "properties": micradar.wprotocolmode }
              }
          },
    0x05: {
      "name": "Status",
      "word": {
        0x01: { "name": "Initialization",
                "properties": micradar.winitstatus },
        0x07: { "name": "Scene Mode",
                "properties": micradar.wscenemode },
        0x08: { "name": "Sensitivity",
                "properties": micradar.wsensitivity }
              }
          },
    0x80: {
      "name": "Human",
      "word": {
        0x01: { "name": "Presence",
                "properties": micradar.woccupancy },
        0x02: { "name": "Activity",
                "properties": micradar.wactivity },
        0x03: { "name": "Body Movement Parameter" },
        0x0A: { "name": "Unoccupied Delay",
                "properties": micradar.wduration,
                "config": true },
        0x0B: { "name": "Motion",
                "properties": micradar.wmovement },
              }
          },
    0x08: {
      "name": "Open Function",
      "word": {
        0x00: { "name": "Switch",
                "properties": micradar.wonoff,
                "config": true },
        0x01: { "name": "Report",
                "properties": ["Static Energy", "Static Distance", "Motion Energy", "Motion Distance", "Movement Speed"] },
        0x06: { "name": "Motion",
                "properties": micradar.wmovement },
        0x07: { "name": "Body Movement Parameter" },
        0x08: { "name": "Presence Energy Threshold" },
        0x09: { "name": "Motion Amplitude Trigger Threshold",
        "config": true },
        0x0A: { "name": "Presence Distance",
        "config": true },
        0x0B: { "name": "Motion Distance",
        "config": true },
        0x0C: { "name": "Motion Trigger Time",
        "config": true },
        0x0C: { "name": "Motion to Rest Time",
        "config": true },
        0x0D: { "name": "Unoccupied State Time",
        "config": true }
              }
          },
      }

  var ser  # create serial port object

  def write2buffer(l, target)
    target.insert(l.find("name"),l.find("properties") != nil ? l["properties"][0x00] : 0)
  end

  # populate buffer and ctl_buffer with control words from word table and default values (0x00)
  def buffer_init()
    for k : self.word.keys()
      if k == 0x05
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

  # def op_buffer_init()
  #   for l : self.word[0x08]["word"].keys()
  #     if k == 0x05
  #     self.cfg_buffer.insert(self.word[k].find("name"),{})
  #       for l : self.word[k]["word"]
  #         self.write2buffer(l, self.cfg_buffer[self.word[k]["name"]])
  #       end
  #     end
  #   end
  #   for k : self.word.keys()
  #     if k > 127
  #       self.buffer.insert(self.word[k].find("name"),{})
  #       for l : self.word[k]["word"]
  #         if l.find("config") != nil
  #           self.write2buffer(l, self.cfg_buffer[self.word[0x05]["name"]])            
  #         else
  #           self.write2buffer(l, self.buffer[self.word[k]["name"]])
  #         end
  #       end 
  #     end
  #   end
  # end  

  # intialize the serial port, if unspecified Tx/Rx are GPIO 1/3
  def init(tx, rx)
    if !tx   tx = gpio.pin(gpio.TXD) end
    if !rx   rx = gpio.pin(gpio.RXD) end
    self.ser = serial(rx, tx, 115200, serial.SERIAL_8N1)
    tasmota.add_driver(self)
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
    var ret = []
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
    print("MicR: Sent =", str(payload_bin))
    logr = f"command payload {payload_bin} sent"
    end
    self.publish2log(logr, 2)
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
    self.send("08","00","0F")
    self.send("05","87","0F")
    self.send("05","88","0F")
    self.send("80","8A","0F")
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
    if self.buffer.find(a1) != nil 
      if self.buffer[a1].find(a2) != data
        self.buffer[a1].setitem(a2,data)
        print(f"Buffer update {a1}: {a2} with {data}")  
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

  def calc_distance(d)
    d = real(d)*0.5 # multiplier 50 because distance is in 0.5m increments 
    return d
  end

  def parse_openprotocol(msg)
    # 0: 1B Presence energy value
    # 1: 1B Static distance
    # 2: 1B Motion energy
    # 3: 1B Movement distance
    # 4: 1B Speed information
    var field   = self.id_name(msg)
    var cw      = self.id_cw(msg)
    var data = []
    var result = {}
      for i:6..5+msg[5]
       data.push(msg.get(i,1)) # push current iteration to list
    end
    data.setitem(1,self.calc_distance(data[1])) # calculate static distance
    data.setitem(3,self.calc_distance(data[3])) # calculate movement distance
    data.setitem(4,data[4] == 0 ? 0 : self.calc_distance(data[4]-10)) # calculate movement distance
    for i : 0 .. size(data)-1
      result.insert(self.word[msg[2]]["word"][msg[3]]["properties"][i],data[i])
    end
    # print("OP result",result)    
    micradar.op_buffer = result
    self.publish2log(json.dump(result), 2)
    var pubtopic = "tele/" + topic + "/OPENPROTOCOL"

    mqtt.publish(pubtopic, json.dump(result), false)
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
              if msg[2] == 0x05 || self.word[msg[2]]['word'][msg[3]].find("config")
                self.parse_config(msg)
                if msg[3] == 0x01
                  self.get_config()
                end
              elif msg[2] == 0x08 # Open reporting
                print("Open report received", msg)
                  if msg[5] == 0x05
                    self.parse_openprotocol(msg)
                  if msg[3] == 0x00 self.opbool = msg[6] end
                    else
                    self.parse_message(msg)
                  end
              else
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

def set_scene(cmd, idx, payload, payload_json)
  print(type(payload))
  payload = int(payload)
  var opt = [1,2,3,4]
  var ctl = "05"
  var cmw = "07"
  var val = "0F"
  if opt.find(int(payload)) != nil
    val = f"{payload:.2i}"
  else
    cmw = "87"
    log("MicR: Set scene. Accepted value range is 1 - 4. No payload shows current configuration")
  end
  radar.send(ctl,cmw,val)
  tasmota.resp_cmnd_done()
end

tasmota.add_cmd('SetScene', set_scene)

def set_sensitivity(cmd, idx, payload, payload_json)
  var opt = [1,2,3]
  var ctl = "05"
  var cmw = "08"
  var val = "0F"
  if opt.find(int(payload)) != nil
    val = f"{payload:.2i}"
  else
    cmw = "88"
    log("MicR: Set unoccupancy delay. Accepted value range is 0 - 8. No payload shows current configuration")
  end
  radar.send(ctl,cmw,val)
  tasmota.resp_cmnd_done()
end

tasmota.add_cmd('SetSensitivity', set_sensitivity)

def set_delay(cmd, idx, payload, payload_json)
  var ctrlword = "80"
  var cmndword = "0A"
  var val = "0F"
  if int(payload) < 7 && int(payload) >= 0
    val = f"{payload:.2i}"
  else
    cmndword = int(cmndword) + 128
    log("MicR: Set unoccupancy delay. Accepted value range is 0 - 8. No payload shows current configuration")
  end
  radar.send(ctrlword, cmndword, val)
  tasmota.resp_cmnd_done()
end
  
tasmota.add_cmd('SetDelay', set_delay)

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

tasmota.add_rule("system#boot", /-> radar.restart() ) # set rule to restart radar on system boot in order to populate sensors