# impExplorer Conctr example code #

This example code reads the following sensors on the impExplorer:
* temperature
* pressure
* humidity
* acceleration (x, y and z)
* light level
* signal stength (rssi)

The values are send to Conctr. You will need to configure the Conctr application, including the API key, and model id in the Agent code.

The impExplorer goes into deep sleep after it takes the sensor readings. 
The accelerometer is setup to wake the impExplorer when it detects a shake.

There is a user configuration page hosted by the agent.
Once you know the agent URL you can open it in a browser to configure the device

