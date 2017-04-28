// Copyright (c) 2017 Mystic Pants Pty Ltd
// This file is licensed under the MIT License
// http://opensource.org/licenses/MIT

// Import Libraries
#require "ConnectionManager.class.nut:1.0.2"
#require "WS2812.class.nut:2.0.2"
#require "HTS221.class.nut:1.0.0"
#require "LPS22HB.class.nut:1.0.0"
#require "LIS3DH.class.nut:1.3.0"
#require "conctr.device.class.nut:1.0.0"


// Default configuration of the sleep pollers
const DEFAULT_POLLFREQ1 = 172800;
const DEFAULT_POLLFREQ2 = 86400;
const DEFAULT_POLLFREQ3 = 18000;
const DEFAULT_POLLFREQ4 = 3600;
const DEFAULT_POLLFREQ5 = 900;

// Constants
const LPS22HB_ADDR_IE = 0xB8; // Imp explorer
const LPS22HB_ADDR_ES = 0xBE; // Sensor node
const LIS3DH_ADDR = 0x32;
const POLL_TIME = 900;
const VOLTAGE_VARIATION = 0.1;
const NO_WIFI_SLEEP_DURATION = 60;
const DEBUG = 1;

// Hardware type enumeration
enum HardwareType {
    environmentSensor,
    impExplorer
}

class ImpExplorer {

    reading = null;
    config = null;

    _processesRunning = 0;
    _pollRunning = false;

    constructor() {

        reading = {
            "pressure": null,
            "temperature": null,
            "humidity": null,
            "battery": null,
            "acceleration_x": null,
            "acceleration_y": null,
            "acceleration_z": null,
            "light": null,
            "rssi": null
        }


        config = {
            "pollFreq1": DEFAULT_POLLFREQ1,
            "pollFreq2": DEFAULT_POLLFREQ2,
            "pollFreq3": DEFAULT_POLLFREQ3,
            "pollFreq4": DEFAULT_POLLFREQ4,
            "pollFreq5": DEFAULT_POLLFREQ5,
            "tapSensitivity": 2,
            "tapEnabled": true,
        }

        agent.on("config", setConfig.bindenv(this));
    }


    // function that requests agent for configs
    // 
    // @params none
    // @returns none
    // 
    function init() {
        
        // Read the config from nv
        if ("nv" in getroottable()) {
            foreach (k,v in ::nv) {
                if (k in config) {
                    config[k] <- v;
                }
            }
        }
        
        // Write back to nv
        ::nv <- config;
    }
    

    // function that sets the configs
    //  
    // @param  newconfig - object containing the new configurations
    // @returns none
    // 
    function setConfig(newconfig) {
        if (typeof newconfig == "table") {

            local dbg = "Setting config: ";
            foreach (k, v in newconfig) {
                config[k] <- v;
                dbg += k + " = " + v + ", ";
            }
            if (DEBUG) server.log(dbg);
            
            if (config.tapEnabled) {
                accel.configureClickInterrupt(true, LIS3DH.DOUBLE_CLICK, config.tapSensitivity, 15, 10, 300);
            } else {
                accel.configureClickInterrupt(false);
            }
            
            // Write back to nv
            ::nv <- config;
            
        }
    }
    

    // function that takes the sensor readings
    // 
    // @param     none
    // @returns   none
    // 
    function poll() {

        if (_pollRunning) return;
        _pollRunning = true;
        _processesRunning = 0;

        // Get the accelerometer data
        _processesRunning++;
        accel.getAccel(function(val) {
            reading.acceleration_x = val.x;
            reading.acceleration_y = val.y;
            reading.acceleration_z = val.z;
            // if (DEBUG) server.log(format("Acceleration (G): (%0.2f, %0.2f, %0.2f)", val.x, val.y, val.z));

            decrementProcesses();
        }.bindenv(this));

        // Get the temp and humid data
        _processesRunning++;
        tempHumid.read(function(result) {
            if ("error" in result) {
                if (DEBUG) server.log("tempHumid: " + result.error);
            } else {
                // This temp sensor has 0.5 accuracy so it is used for 0-40 degrees.
                reading.temperature = result.temperature;
                reading.humidity = result.humidity;
                if (DEBUG) server.log(format("Current Humidity: %0.2f %s, Current Temperature: %0.2f °C", result.humidity, "%", result.temperature));
            }

            decrementProcesses();
        }.bindenv(this));

        // Get the pressure data
        _processesRunning++;
        pressureSensor.read(function(result) {
            if ("err" in result) {
                if (DEBUG) server.log("pressureSensor: " + result.err);
            } else {
                // Note the temp sensor in the LPS22HB is only accurate to +-1.5 degrees. 
                // But it has an range of up to 65 degrees.
                // Hence it is used if temp is greater than 40.
                if (result.temperature > 40) reading.temperature = result.temperature;
                reading.pressure = result.pressure;
                if (DEBUG) server.log(format("Current Pressure: %0.2f hPa, Current Temperature: %0.2f °C", result.pressure, result.temperature));
            }

            decrementProcesses();
        }.bindenv(this));

        // Read the light level
        reading.light = hardware.lightlevel();
        if (DEBUG) server.log("Ambient Light: " + reading.light);

        // Read the signal strength
        reading.rssi = imp.getrssi();
        if (DEBUG) server.log("Signal strength: " + reading.rssi);

        // Read the battery voltage
        if (hardwareType == HardwareType.environmentSensor) {
            reading.battery = getBattVoltage();
        } else {
            reading.battery = 0;
        }

        // Toggle the LEDs on
        if (hardwareType == HardwareType.environmentSensor) {
            ledgreen.write(0);
            ledblue.write(0);
        } else {
            hardware.pin1.configure(DIGITAL_OUT, 1);
            rgbLED.set(0, [0, 100, 100]).draw();
        }

        _processesRunning++;
        imp.wakeup(0.4, function() {
            // Toggle the LEDs off
            if (hardwareType == HardwareType.environmentSensor) {
                ledgreen.write(1);
                ledblue.write(1);
            } else {
                hardware.pin1.configure(DIGITAL_OUT, 0);
            }

            decrementProcesses();
        }.bindenv(this));


    }
    

    // function that posts the readings and sends the device to sleep
    // 
    // @param     none
    // @returns   none
    // 
    function postReadings() {
        
        // RSSI doesn't get a value when offline, add it now if required
        if (reading.rssi == 0) reading.rssi = imp.getrssi();
        // Add the location after a blinkup or new squirrel
        if (hardware.wakereason() == WAKEREASON_BLINKUP || hardware.wakereason() == WAKEREASON_NEW_SQUIRREL) {
            reading._location <- imp.scanwifinetworks();
        }
        
        // Send the reading
        conctr.sendData(reading);
        
        // Determine how long to wait before sleeping
        local sleepdelay = 20;
        if (hardware.wakereason() == WAKEREASON_TIMER) {
            sleepdelay = 0.5;
        } else if (hardware.wakereason() == WAKEREASON_PIN) {
            sleepdelay = 5;
            agent.send("config", true);
        }

        // Wait the specified time
        server.flush(10);
        imp.wakeup(sleepdelay, function() {

            // Determine how long to sleep for
            local sleepTime = calcSleepTime(reading.battery, hardwareType);

            // Now actually sleep
            wakepin.configure(DIGITAL_IN_WAKEUP);
            server.sleepfor(sleepTime);
            
        }.bindenv(this));
    }


    // function that reads the battery voltage
    // 
    // @param     none
    // @returns   battVoltage - the detected battery voltage
    // 
    function getBattVoltage() {
        local firstRead = batt.read() / 65535.0 * hardware.voltage();
        local battVoltage = batt.read() / 65535.0 * hardware.voltage();
        local pollArray = [];
        if (math.abs(firstRead - battVoltage) < VOLTAGE_VARIATION) {
            return battVoltage;
        } else {
            for (local i = 0; i < 10; i++) {
                pollArray.append(batt.read() / 65535.0 * hardware.voltage());
            }
            return array_avg(pollArray);
        }
    }


    // function posts readings if no more processes are running
    // 
    // @param     none
    // @returns   none
    // 
    function decrementProcesses() {
        if (--_processesRunning <= 0) {
            if (cm.isConnected()) {
                postReadings();   
            } else {
                // TODO Handle not connected to wifi
                cm.onNextConnect(postReadings.bindenv(this));
                cm.connect();
            }

        }
    }
    

    // function that calculates sleep time
    // 
    // @param     battVoltage - the read battery voltage
    // @returns   sleepTime - duration for the imp to sleep
    // 
    function calcSleepTime(battVoltage, hardwareType = HardwareType.impExplorer) {
        local sleepTime;
        if (hardwareType == HardwareType.impExplorer) {
            // The impExplorer doesn't have a battery reading so always use pollFreq5
            sleepTime = config.pollFreq5;
            if (DEBUG) server.log("Battery not readable so assuming full");
        } else if (battVoltage < 0.8) {
            // Poll only once every two days
            sleepTime = config.pollFreq1;
            if (DEBUG) server.log("Battery voltage critical: " + battVoltage);
        } else if (battVoltage < 1.5) {
            // Poll only once every day
            sleepTime = config.pollFreq2;
            if (DEBUG) server.log("Battery voltage low: " + battVoltage);
        } else if (battVoltage < 2.0) {
            // Poll only once every 5 hours
            sleepTime = config.pollFreq3;
            if (DEBUG) server.log("Battery voltage medium: " + battVoltage);
        } else if (battVoltage < 2.5) {
            // Poll only once an hour
            sleepTime = config.pollFreq4;
            if (DEBUG) server.log("Battery voltage high: " + battVoltage);
        } else {
            // Poll every 15 min
            sleepTime = config.pollFreq5;
            if (DEBUG) server.log("Battery voltage full: " + battVoltage);
        }

        return sleepTime;
    }


    // function that returns an average of an array
    // 
    // @param     array - input array of numbers
    // @returns average - average of array
    // 
    function array_avg(array) {
        local sum = 0;
        local average = 0
        for (local i = 0; i < array.len(); i++) {
            sum += array[i];
        }
        average = sum / (array.len());
        return average
    }

}


//=============================================================================
// START OF PROGRAM

// Connection manager
cm <- ConnectionManager({ "blinkupBehavior": ConnectionManager.BLINK_ALWAYS, "stayConnected": false });
imp.setsendbuffersize(8096);

// Checks hardware type
if ("pinW" in hardware) {
    hardwareType <- HardwareType.environmentSensor;
    // server.log("This is an Environmental Sensor")
} else {
    hardwareType <- HardwareType.impExplorer;
    // server.log("This is an impExplorer")
}

// Configures the pins depending on hardware type
if (hardwareType == HardwareType.environmentSensor) {
    batt <- hardware.pinH;
    batt.configure(ANALOG_IN);
    wakepin <- hardware.pinW;
    ledblue <- hardware.pinP;
    ledblue.configure(DIGITAL_OUT, 1);
    ledgreen <- hardware.pinU;
    ledgreen.configure(DIGITAL_OUT, 1);
    i2cpin <- hardware.i2cAB;
    i2cpin.configure(CLOCK_SPEED_400_KHZ);
} else {
    batt <- null;
    wakepin <- hardware.pin1;
    ledblue <- null;
    ledgreen <- null;
    i2cpin <- hardware.i2c89;
    i2cpin.configure(CLOCK_SPEED_400_KHZ);
    spi <- hardware.spi257;
    spi.configure(MSB_FIRST, 7500);
    rgbLED <- WS2812(spi, 1);
}

// Initialise all the attached devices
accel <- LIS3DH(i2cpin, LIS3DH_ADDR);
accel.setDataRate(100);
accel.configureClickInterrupt(true, LIS3DH.DOUBLE_CLICK, 2, 15, 10, 300);
accel.configureInterruptLatching(true);
pressureSensor <- LPS22HB(i2cpin, hardwareType == HardwareType.environmentSensor ? LPS22HB_ADDR_ES : LPS22HB_ADDR_IE);
tempHumid <- HTS221(i2cpin);
tempHumid.setMode(HTS221_MODE.ONE_SHOT, 7);
conctr <- Conctr({"sendLoc": false});

// Start the application
impExplorer <- ImpExplorer();

// Start polling after the imp is idle
imp.onidle(function(){
    impExplorer.init();
    impExplorer.poll();
}.bindenv(this));
