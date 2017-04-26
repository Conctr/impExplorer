// Copyright (c) 2017 Mystic Pants Pty Ltd
// This file is licensed under the MIT License
// http://opensource.org/licenses/MIT

#require "Rocky.class.nut:1.3.0"
#require "conctr.agent.class.nut:1.0.0"

// Conctr configuration
const APP_ID = "Put your APP_ID here";
const API_KEY = "Put your API_KEY here";
const MODEL = "Put your MODEL here";

// Default configuration of the hardware
const DEFAULT_POLLFREQ1 = 172800;
const DEFAULT_POLLFREQ2 = 86400
const DEFAULT_POLLFREQ3 = 18000;
const DEFAULT_POLLFREQ4 = 3600;
const DEFAULT_POLLFREQ5 = 900;

class ImpExplorer {

    _conctr = null;
    _rocky = null;
    _savedData = null;
    _configChanged = true;

    constructor(conctr, rocky) {

        _conctr = conctr;
        _rocky = rocky;

        local initialData = server.load();
        if (!("config" in initialData)) {

            // Set the default values and save them to persistant storage
            _savedData = {
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
                },

                config = {

                    "pollFreq1": DEFAULT_POLLFREQ1,
                    "pollFreq2": DEFAULT_POLLFREQ2,
                    "pollFreq3": DEFAULT_POLLFREQ3,
                    "pollFreq4": DEFAULT_POLLFREQ4,
                    "pollFreq5": DEFAULT_POLLFREQ5,
                    "tapSensitivity": 2,
                    "tapEnabled": true
                }
            }
            server.save(_savedData);

        } else {

            _savedData = initialData;

        }

        // Set up the agent API - just return standard web page HTML string
        _rocky.get("/", function(context) {
            context.send(200, format(HTML_ROOT, http.agenturl()));
        }.bindenv(this));

        // Request for data from /config endpoint
        _rocky.get("/config", function(context) {
            context.send(200, _savedData);
        }.bindenv(this));

        // Config submission at the /config endpoint
        _rocky.post("/config", function(context) {       
            setConfig(context.req.body)
            sendConfig();
            context.send(200, "OK");
        }.bindenv(this));

        // Register the function to handle data messages from the device
        device.on("reading", postReading.bindenv(this));        

        // Register the request-for-config message
        device.on("config", sendConfig.bindenv(this));      

    }


    // Updates the in-memory and persistant data table
    // 
    // @param     newconfig - a table with the new configuration values
    // @returns   none
    // 
    function setConfig(newconfig) {
        if (typeof newconfig == "table") {
            foreach (k, v in newconfig) {
                if (typeof v == "string") {
                    if (v.tolower() == "true") {
                        v = true;
                    } else if (v.tolower() == "false") {
                        v = false;
                    } else {
                        v = v.tointeger();
                    }
                }
                _savedData.config[k] <- v;
            }
            _configChanged = true;
            return server.save(_savedData);
        } else {
            return false;
        }
    }


    // function that sends data to Conctr
    // 
    // @param     reading - the sensor readings to be posted
    // @returns    none - 
    // 
    function postReading(reading) {
        
        _conctr.sendData(reading, function(err, response) {
            if (err) {
                server.error("Conctr::sendData: " + err);
            } else {
                server.log("Readings sent to Conctr. Status code: " + response.statusCode);
            }
        }.bindenv(this));
        
    }
    

    // function that sends the config to device
    // 
    // @param     none
    // @returns   none
    // 
    function sendConfig(d = null) {
        // Send back the config to the device
        device.send("config", _savedData.config);        
    }


}


HTML_ROOT <- @"
<!DOCTYPE html>
<html>

<head>
    <title>Environment Data</title>
    <link rel='stylesheet' href='https://netdna.bootstrapcdn.com/bootstrap/3.1.1/css/bootstrap.min.css'>
    <meta name='viewport' content='width=device-width, initial-scale=1.0'>
    <style>
    .center {
        margin-left: auto;
        margin-right: auto;
        margin-bottom: auto;
        margin-top: auto;
    }
    </style>
</head>

<body>
    <div class='container'>
        <h2 class='text-center'>User Settings</h2>
        <br>
        <div class='controls'>
            <div class='update-button'>
                <form id='config-form'>
                    <div>
                        <label>Tap Sensitivity(Gs):</label>&nbsp;
                        <input id='tapSensitivity'></input>
                        <input type='checkbox' id='tapEnabled' name='tapEnabled' value='tapEnabled'>Tap Enabled</input>
                    </div>
                    <div>
                        <label>Poll time when battery critical:</label>&nbsp;
                        <input id='pollFreq1'></input> seconds
                    </div>
                    <div>
                        <label>Poll time when battery low:</label>&nbsp;
                        <input id='pollFreq2'></input> seconds
                    </div>
                    <div>
                        <label>Poll time when battery medium:</label>&nbsp;
                        <input id='pollFreq3'></input> seconds
                    </div>
                    <div>
                        <label>Poll time when battery high:</label>&nbsp;
                        <input id='pollFreq4'></input> seconds
                    </div>
                    <div>
                        <label>Poll time when battery full:</label>&nbsp;
                        <input id='pollFreq5'></input> seconds
                    </div>
                    <div>
                        <button type='submit' id='update-button'>Update Config</button>
                        <label id='submitResult' style='color:blue'></label>
                    </div>
                </form>
            </div>
        </div>
        <!-- controls -->
        <br>
        <small>From: <span id='agenturl'>Unknown</span></small>
    </div>
    <!-- container -->
    
    
    <script src='https://cdnjs.cloudflare.com/ajax/libs/jquery/3.2.1/jquery.min.js'></script>
    <script>
        
        var agenturl = '%s';

        function getConfigInput(e) {
            var config = {
                'tapSensitivity': parseInt($('#tapSensitivity').val()),
                'tapEnabled': $('#tapEnabled').val() == 'tapEnabled',
                'pollFreq1': parseInt($('#pollFreq1').val()),
                'pollFreq2': parseInt($('#pollFreq2').val()),
                'pollFreq3': parseInt($('#pollFreq3').val()),
                'pollFreq4': parseInt($('#pollFreq4').val()),
                'pollFreq5': parseInt($('#pollFreq5').val())
            };
            
            setConfig(config);
            $('#name-form').trigger('reset');
            return false;
        }


        function updateReadout(data) {
            $('#tapSensitivity').val(data.tapSensitivity);
            $('#tapEnabled').prop('checked', data.tapEnabled);
            $('#pollFreq1').val(data.pollFreq1);
            $('#pollFreq2').val(data.pollFreq2);
            $('#pollFreq3').val(data.pollFreq3);
            $('#pollFreq4').val(data.pollFreq4);
            $('#pollFreq5').val(data.pollFreq5);
            setTimeout(function() {
                getConfig(updateReadout);
            }, 120000);
        }


        function getConfig(callback) {
            $.ajax({
                url: agenturl + '/config',
                type: 'GET',
                success: function(response) {
                    if (callback && ('config' in response)) {
                        console.log('Successfully loaded from agent');
                        callback(response.config);
                        $('#submitResult').text('Loaded');
                        setTimeout(function() {
                            $('#submitResult').text('');
                        }, 2000);
                    }
                }
            });
        }


        function setConfig(config) {
            $.ajax({
                url: agenturl + '/config',
                contentType: 'application/json; charset=utf-8',
                dataType: 'text',
                type: 'POST',
                data: JSON.stringify(config),
                
                error: function(jqXHR, textStatus, errorThrown) {
                    console.log('Failed to sent to agent: ' + errorThrown);
                    $('#submitResult').text(textStatus);
                    setTimeout(function() {
                        $('#submitResult').text('');
                    }, 4000);
                },
                
                success: function(response) {
                    console.log('Successfully sent to agent');
                    $('#submitResult').text('Updated');
                    setTimeout(function() {
                        $('#submitResult').text('');
                    }, 2000);
                }
            });
        }
        
        // Initialise the display
        $(function() {
            $('#agenturl').text(agenturl);
            getConfig(updateReadout);
            $('.update-button button').on('click', getConfigInput);
        })

    </script>
</body>

</html>
"


//=============================================================================
// START OF PROGRAM

// Prepare the prerequisite classes
rocky <- Rocky();
conctr <- Conctr(APP_ID, API_KEY, MODEL);

// Start the application
impExplorer <- ImpExplorer(conctr, rocky);


