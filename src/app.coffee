Bacon = require('baconjs')
io = require('socket.io-client')
PowerMate = require './PowerMate'
unirest = require('unirest')
winston = require('winston')
R = require('ramda')

houmioServer = process.env.HOUMIO_SERVER || "http://localhost:3000"
houmioSiteKey = process.env.HOUMIO_SITEKEY || "devsite"

unirest
  .get houmioServer + "/api/site/" + houmioSiteKey
  .headers {'Accept': 'application/json' }
  .end (res) ->
    global.site = res.body

onHoumioSocketConnect = ->
  winston.info "Connected to #{houmioServer}"
  houmioSocket.emit "clientReady", { siteKey: houmioSiteKey }

onHoumioSocketReconnect = ->
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

onHoumioSocketSetLightState = (lightState) ->
  light = R.find R.propEq('_id', lightState._id), global.site.lights
  if light?
    light.on = lightState.on
    light.bri = lightState.bri

winston.info "Using HOUMIO_SERVER=#{houmioServer}"
winston.info "Using HOUMIO_SITEKEY=#{houmioSiteKey}"
houmioSocket = io houmioServer, { timeout: 60000, reconnectionDelay: 1000, reconnectionDelayMax: 10000 }
houmioSocket.on 'connect', onHoumioSocketConnect
houmioSocket.on 'reconnect', onHoumioSocketReconnect
houmioSocket.on 'connect_error', onHoumioSocketConnectError
houmioSocket.on 'reconnect_error', onHoumioSocketReconnectError
houmioSocket.on 'connect_timeout', onHoumioSocketConnectTimeout
houmioSocket.on 'disconnect', onHoumioSocketDisconnect
houmioSocket.on 'unknownSiteKey', onHoumioSocketUnknownSiteKey
houmioSocket.on 'setLightState', onHoumioSocketSetLightState

exit = (msg) ->
  winston.info msg
  pm.close()
  process.exit 1

calculateNewLightState = (lightState, briDelta) ->
  bri = Math.max(Math.min(lightState.bri+briDelta, 255), 0)
  onB = !(bri is 0)
  { bri: bri, on: onB }

pm = new PowerMate()

pm.on 'buttonDown', ->
  light = global.site.lights[0]
  houmioSocket.emit 'apply/all', { on: !light.on, bri: if light.on then 0 else 255 }

deltas = Bacon.fromBinder (sink) ->
  pm.on 'wheelTurn', sink
  ( -> )

deltas
  .bufferWithTime(300)
  .map R.sum
  .map R.multiply(3)
  .onValue (bufferedDelta) ->
    houmioSocket.emit 'apply/all', calculateNewLightState(global.site.lights[0], bufferedDelta)