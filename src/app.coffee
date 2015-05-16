Bacon = require('baconjs')
io = require('socket.io-client')
PowerMate = require './PowerMate'
unirest = require('unirest')
winston = require('winston')
R = require('ramda')

exit = (msg) ->
  winston.info msg
  process.exit 1

onHoumioSocketConnect = (houmioSocket) -> () ->
  winston.info "Connected to #{houmioServer}"
  houmioSocket.emit "clientReady", { siteKey: houmioSiteKey }

onHoumioSocketReconnect = (houmioSocket) -> () ->
  winston.info "Reconnected to #{houmioServer}"
  houmioSocket.emit "clientReady", { siteKey: houmioSiteKey }

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

onHoumioSocketSetLightState = (site) -> (lightState) ->
  light = R.find R.propEq('_id', lightState._id), site.lights
  if light?
    light.on = lightState.on
    light.bri = lightState.bri

adjustBri = (briDelta) -> (light) ->
  bri = Math.max(Math.min(light.bri+briDelta, 255), 0)
  onB = !(bri is 0)
  { _id: light._id, bri: bri, on: onB }

applyLight = (houmioSocket) -> (light) ->
  houmioSocket.emit 'apply/light', light

toggleAllLights = (site, houmioSocket) -> () ->
  onObjects = R.map R.pick(["on"]), site.lights
  onBooleans = R.flatten (R.map R.values, onObjects)
  allOff = R.all R.not, onBooleans
  newState = if allOff then { on: true, bri: 255 } else { on: false, bri: 0 }
  houmioSocket.emit 'apply/all', newState

adjustAllLights = (site, houmioSocket) -> (briDelta) ->
  adjustedLights = R.map adjustBri(briDelta), site.lights
  R.forEach applyLight(houmioSocket), adjustedLights

wheelTurnsToDeltaStream = (pm) ->
  Bacon.fromBinder (sink) ->
    pm.on 'wheelTurn', sink
    ( -> )

# Connect to server and start listening to PowerMate events

houmioServer = process.env.HOUMIO_SERVER || "http://localhost:3000"
houmioSiteKey = process.env.HOUMIO_SITEKEY || "devsite"
winston.info "Using HOUMIO_SERVER=#{houmioServer}"
winston.info "Using HOUMIO_SITEKEY=#{houmioSiteKey}"

unirest
  .get houmioServer + "/api/site/" + houmioSiteKey
  .headers {'Accept': 'application/json' }
  .end (res) ->
    site = res.body
    houmioSocket = io houmioServer, { timeout: 60000, reconnectionDelay: 1000, reconnectionDelayMax: 10000 }
    houmioSocket.on 'connect', onHoumioSocketConnect(houmioSocket)
    houmioSocket.on 'reconnect', onHoumioSocketReconnect(houmioSocket)
    houmioSocket.on 'connect_error', onHoumioSocketConnectError
    houmioSocket.on 'reconnect_error', onHoumioSocketReconnectError
    houmioSocket.on 'connect_timeout', onHoumioSocketConnectTimeout
    houmioSocket.on 'disconnect', onHoumioSocketDisconnect
    houmioSocket.on 'unknownSiteKey', onHoumioSocketUnknownSiteKey
    houmioSocket.on 'setLightState', onHoumioSocketSetLightState(site)
    pm = new PowerMate()
    pm.on 'buttonDown', toggleAllLights(site, houmioSocket)
    wheelTurnsToDeltaStream(pm)
      .bufferWithTime(300)
      .map R.sum
      .map R.multiply(2)
      .onValue adjustAllLights(site, houmioSocket)
