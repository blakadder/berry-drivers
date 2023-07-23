# mmWave 24Ghz radar Tasmota driver v1.0 | code by blakadder
# Works with:
# Seeedstudio MR24HPC1 - https://www.seeedstudio.com/24GHz-mmWave-Sensor-Human-Static-Presence-Module-Lite-p-5524.html
# MicRadar R24DVD1 - https://s.click.aliexpress.com/e/_DEaKFRN
# source on https://github.com/blakadder/micradar-berry

# Does not include "Underlying Open function" mode

import string

var topic = tasmota.cmd('Status ', true)['Status']['Topic']

class micradar : Driver

  var presence, motion, bmp, proximity

  static buffer = {
    0x01: "Unknown",
    0x02: "Unknown",
    0x03: 0,
    0x0B: "Unknown",
  }

  static header = bytes("5359")
  static endframe = "5443"

  static wpresence = {
    0x00: "Unoccupied",
    0x01: "Occupied"
  }

  static wproximity = {
    0x00: "None",
    0x01: "Approaching",
    0x02: "Leaving"
  }

  static wactivity = {
    0x00: "None",
    0x01: "Motionless",
    0x02: "Active"
  }

  static wsensitivity = {
    0x00: "None",
    0x01: "2m",
    0x02: "3m",
    0x03: "4m" # default setting
  }

  static wscenemode = {
    0x00: "Scene mode not set",
    0x01: "Living Room",
    0x02: "Bedroom",
    0x03: "Bathroom",
    0x04: "Area Detection"
  }

  # duration from "presence" to "no presence", default is 30s
  static wduration = {
    0x00: "None",
    0x01: "10s",
    0x02: "30s", # default setting
    0x03: "1m",
    0x04: "2m",
    0x05: "5m",
    0x06: "10m",
    0x07: "30m",
    0x08: "60m"
  }

  static winitstatus = {
    0x00: "Completed",
    0x01: "Incomplete",
    0x0F: "Completed",
  }

  static wprotocolmode = {
    0x00: "Standard",
    0x01: "Advanced"
  }

  static wonoff = {
    0x00: "OFF",
    0x01: "ON"
  }

  static word = {
    0x01: { 
      0x01: "Heartbeat", 
      0x01: "Reset", 
    },
    0x02: {
      0xA1: "Product Model", 
      0xA2: "Product ID",
      0xA3: "Hardware Model",
      0xA4: "Firmware Version",
    },
    0x05: {
      0x01: ["Initialization", micradar.winitstatus],
      0x07: ["Scene", micradar.wscenemode],
      0x08: ["Sensitivity", micradar.wsensitivity],
      0x81: ["Initialization Status", micradar.winitstatus],
      0x87: ["Scene Setting", micradar.wscenemode],
      0x88: ["Sensitivity Setting", micradar.wsensitivity],
    },
    0x08: {
      0x00: ["Protocol Mode", micradar.wprotocolmode],
      0x80: ["Information Output", micradar.wonoff],
    },
    0x80: {
      0x01: ["Presence", micradar.wonoff],
      0x02: ["Motion", micradar.wactivity],
      0x03: ["Body Movement Parameter"],
      0x0A: ["Duration", micradar.wduration],
      0x0B: ["Proximity", micradar.wproximity],
      0x81: ["Presence", micradar.wpresence],
      0x82: ["Motion", micradar.wactivity],
      0x83: ["Body Movement Parameter"],
      0x8A: ["Duration", micradar.wduration],
      0x8B: ["Proximity", micradar.wproximity],
    }
  }
  
  var ser  # create serial port object
  
  # intialize the serial port, Tx/Rx are set in module/template
  def init(tx, rx)
    if !tx   tx = gpio.pin(gpio.TXD) end
    if !rx   rx = gpio.pin(gpio.RXD) end
    self.ser = serial(rx, tx, 115200, serial.SERIAL_8N1)
    tasmota.add_driver(self)
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
          checksum &= 0xFF  # ensure the checksum stays within 8 bits
      end
      return checksum
  end
    
  def encode(ctrlword, cmndword, data)
    var d = bytes().fromhex(data)
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

  def ident_data(msg)
    var converted = msg[3] & 0x7F
    var msgsize = size(self.word[msg[2]][converted])
    var result = msgsize <=1? msg[6] : self.word[msg[2]][converted][1][msg[6]] 
    return result
  end

  def restart()
    self.ser.write(self.encode("01", "02", "0F"))
    print("Reset command sent")
  end
  
  # send a command, format: controlword/commandword/data (if no data "0F" is used)
  def send(d)
    import string
    var dat = string.split(d, "/")
    if size(dat) < 3 dat.push("0F") end
    var payload_bin = self.encode(str(dat[0]), str(dat[1]), str(dat[2]))
    self.ser.write(payload_bin)
    print("MicR: Sent = ", str(payload_bin))
    log("MicR: Sent = " + str(payload_bin), 2)
  end

  def parse_message(msg)
    import mqtt
    var data  = self.ident_data(msg)
    var field = self.word[msg[2]][msg[3]][0] 
    var result 
    if size(self.word[msg[2]][msg[3]]) <= 1
      result = string.format("{\"MicRadar\":{\"%s\":%d}", field, data)
    else
      result = string.format("{\"MicRadar\":{\"%s\":\"%s\"}", field, data)
    end
    # print("MicR:", result)
    log(result, 3)
    var pubtopic = "stat/" + topic + "/SENSOR"
    mqtt.publish(pubtopic, result, false)
  end

  def parse_productinfo(msg)
    import mqtt
    var field = self.word[msg[2]][msg[3]] 
    var data  = msg[6..5+msg[5]].asstring()
    var result = string.format("{\"MicRadar\":{\"%s\":\"%s\"}", field, data)
    log(result, 3)
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
            # print("MicRadar: Raw =", msg)
            if msg[2] == 0x01 # System Functions
              if msg[3] == 0x01 # Heartbeat
                if msg[6] == 0x0F 
                  print('MicR: Heartbeat: OK')
                end
              elif msg[3] == 0x02 # Restart
                if msg[6] == 0x0F 
                  print('MicR: Restarting')
                end
              end
            elif msg[2] == 0x02 # Product Information
              self.parse_productinfo(msg)
            elif msg[2] == 0x05 # Settings
              print(msg)
              self.parse_message(msg)
            else
              if msg[2] == 0x80
              # write active reading to buffer if they fit keys in buffer
                if msg[3] == 0x0A
                  self.parse_message(msg)
                else
                var converted = msg[3] & 0x7F
                  if self.buffer.find(converted) != nil 
                    if self.buffer[converted] != self.ident_data(msg) 
                    self.buffer[converted] = self.ident_data(msg) 
                    self.parse_message(msg)
                    end
                  end
                end
              end
            end
          end
        end  
      end
    end
  end
  
  def json_append()
	var msg = string.format(",\"MicRadar\":{\"Presence\":\"%s\",\"Activity\":\"%s\",\"Body Movement Parameter\":%d,\"Movement\":\"%s\"}",
              self.buffer[0x01],self.buffer[0x02],self.buffer[0x03],self.buffer[0x0B])
    tasmota.response_append(msg)
  end

  def web_sensor()
    if !self.ser return nil end  #- exit if not initialized -#
    import string
    var msg = string.format(
             "{s}Presence{m}%s{e}"..
             "{s}Activity{m}%s{e}"..
             "{s}Body Movement Parameter{m}%d{e}"..
             "{s}Movement{m}%s{e}",
             self.buffer[0x01],self.buffer[0x02],self.buffer[0x03],self.buffer[0x0B])
    tasmota.web_send_decimal(msg)
  end
end

radar=micradar()
tasmota.add_driver(radar)

def scene_set(RadarScene, idx, payload)
  var opts = [1,2,3,4]
  if opts.find(int(payload)) != nil
    radar.send(string.format("05/07/0%d",payload))
    tasmota.resp_cmnd_done()
  else
    radar.send("05/87")
    tasmota.resp_cmnd_done()
  end
end

tasmota.add_cmd('RadarScene', scene_set)

def sensitivity_set(RadarSensitivity, idx, payload)
  var opts = [1,2,3]
  if opts.find(int(payload)) != nil
    radar.send(string.format("05/08/0%d",payload))
    tasmota.resp_cmnd_done()
  else
    radar.send("05/88")
    tasmota.resp_cmnd_done()
  end
end

tasmota.add_cmd('RadarSensitivity', sensitivity_set)

def delay_set(RadarDelay, idx, payload)
  var opts = [0,1,2,3,4,5,6,7,8]
  if opts.find(int(payload)) != nil
    radar.send(string.format("80/0A/0%d",payload))
    tasmota.resp_cmnd_done()
  else
    radar.send("80/8A")
    tasmota.resp_cmnd_done()
  end
end

tasmota.add_cmd('RadarDelay', delay_set)

def restart_cmnd(RadarRestart, idx, payload)
    radar.restart()
    tasmota.resp_cmnd_done()
end

tasmota.add_cmd('RadarRestart', restart_cmnd)

radar.send("05/07")
radar.send("05/08")
radar.send("80/81")
radar.send("80/82")
radar.send("80/83")
radar.send("80/8A")
radar.send("80/8B")