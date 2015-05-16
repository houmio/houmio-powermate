Bacon = require('baconjs')
io = require('socket.io-client')
PowerMate = require './PowerMate'
unirest = require('unirest')
winston = require('winston')
R = require('ramda')

onHoumioSocketConnect = ->
  winston.info "Connected to #{houmioServer}"
  global.houmioSocket.emit "clientReady", { siteKey: houmioSiteKey }

onHoumioSocketReconnect = ->
  winston.info "Reconnected to #{houmioServer}"
  global.houmioSocket.emit "clientReady", { siteKey: houmioSiteKey }

onHoumioSocketConnectError = (err) ->
  winston.info "Connect error to #{houmioServer}: #{err}"

onHoumioSocketReconnectError = (err) ->
  winston.info "Reconnect error to #{houmioServer}: #{err}"

onHoumioSocketConnectTimeout = ->
  winston.info "Connect timeout to #{houmioServer}"

onHoumioSocketDisconnect = ->
  winston.info "Disconnected from #{houmioServer}"

onHoumioSocketUnknownSiteKey = (siteKey) ->
  exit "Server did not accept site key '#{siteKey}'"

onHoumioSocketSetLightState = (lightState) ->
  light = R.find R.propEq('_id', lightState._id), global.site.lights
  if light?
    light.on = lightState.on
    light.bri = lightState.bri

exit = (msg) ->
  winston.info msg
  pm.close()
  process.exit 1

calculateNewLightState = (lightState, briDelta) ->
  bri = Math.max(Math.min(lightState.bri+briDelta, 255), 0)
  onB = !(bri is 0)
  { bri: bri, on: onB }

toggleLight = (light) ->
  { _id: light._id, on: !light.on, bri: if light.on then 0 else 255 }

applyLight = (light) ->
  global.houmioSocket.emit 'apply/light', light

toggleAllLights = ->
  onObjects = R.map R.pick(["on"]), global.site.lights
  onBooleans = R.flatten (R.map R.values, onObjects)
  allOff = R.all R.not, onBooleans
  newState = if allOff then { on: true, bri: 255 } else { on: false, bri: 0 }
  global.houmioSocket.emit 'apply/all', newState

adjustBri = (briDelta) -> (light) ->
  bri = Math.max(Math.min(light.bri+briDelta, 255), 0)
  onB = !(bri is 0)
  { _id: light._id, bri: bri, on: onB }

adjustAllLights = (briDelta) ->
  adjustedLights = R.map adjustBri(briDelta), global.site.lights
  R.forEach applyLight, adjustedLights

wheelTurnsToDeltaStream = (pm) ->
  Bacon.fromBinder (sink) ->
    pm.on 'wheelTurn', sink
    ( -> )

# Start listening to events

houmioServer = process.env.HOUMIO_SERVER || "http://localhost:3000"
houmioSiteKey = process.env.HOUMIO_SITEKEY || "devsite"
winston.info "Using HOUMIO_SERVER=#{houmioServer}"
winston.info "Using HOUMIO_SITEKEY=#{houmioSiteKey}"

unirest
  .get houmioServer + "/api/site/" + houmioSiteKey
  .headers {'Accept': 'application/json' }
  .end (res) ->
    global.site = res.body
    global.houmioSocket = io houmioServer, { timeout: 60000, reconnectionDelay: 1000, reconnectionDelayMax: 10000 }
    global.houmioSocket.on 'connect', onHoumioSocketConnect
    global.houmioSocket.on 'reconnect', onHoumioSocketReconnect
    global.houmioSocket.on 'connect_error', onHoumioSocketConnectError
    global.houmioSocket.on 'reconnect_error', onHoumioSocketReconnectError
    global.houmioSocket.on 'connect_timeout', onHoumioSocketConnectTimeout
    global.houmioSocket.on 'disconnect', onHoumioSocketDisconnect
    global.houmioSocket.on 'unknownSiteKey', onHoumioSocketUnknownSiteKey
    global.houmioSocket.on 'setLightState', onHoumioSocketSetLightState
    pm = new PowerMate()
    pm.on 'buttonDown', toggleAllLights
    wheelTurnsToDeltaStream(pm)
      .bufferWithTime(300)
      .map R.sum
      .map R.multiply(3)
      .onValue adjustAllLights
