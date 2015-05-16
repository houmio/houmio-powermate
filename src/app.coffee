PowerMate = require './PowerMate'

pm = new PowerMate()

pm.on 'buttonDown', ->
  console.log ""

pm.on 'wheelTurn', (delta) ->
  arrow = if delta > 0 then '\u25B2' else '\u25BC'
  output = Array(Math.abs(delta)+1).join(arrow)
  process.stdout.write output + " "
