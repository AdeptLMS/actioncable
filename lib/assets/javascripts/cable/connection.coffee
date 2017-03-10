#= require ./connection_monitor
# Encapsulate the cable connection held by the consumer. This is an internal class not intended for direct user manipulation.
{message_types} = Cable.INTERNAL

class Cable.Connection
  @reopenDelay: 500

  constructor: (@consumer) ->
    {@subscriptions} = @consumer
    @monitor = new Cable.ConnectionMonitor this
    @disconnected = true
    @open()

  send: (data) ->
    if @isOpen()
      @webSocket.send(JSON.stringify(data))
      true
    else
      false

  open: =>
    if @isActive()
      #if @webSocket and not @isState("closed") and not @isOpen
      Cable.log("Attempted to open WebSocket, but existing socket is #{@getState()}")
      false
      #throw new Error("Existing connection must be closed before opening")
    else
      Cable.log("Opening WebSocket, current state is #{@getState()}")
      @uninstallEventHandlers() if @webSocket?
      @webSocket = new Cable.WebSocket(@consumer.url)
      @installEventHandlers()
      @monitor.start()
      true

  close: ({allowReconnect} = {allowReconnect: true}) ->
    @monitor.stop() unless allowReconnect
    @webSocket?.close() if @isActive()

  reopen: ->
    Cable.log("Reopening WebSocket, current state is #{@getState()}")
    if @isActive()
      try
        @close()
      catch error
        Cable.log("Failed to reopen WebSocket", error)
      finally
        Cable.log("Reopening WebSocket in #{@constructor.reopenDelay}ms")
        setTimeout(@open, @constructor.reopenDelay)
    else
      @open()

  isOpen: ->
    @isState("open")

  isActive: ->
    @isState("open", "connecting")

  # Private

  isState: (states...) ->
    @getState() in states

  getState: ->
    return state.toLowerCase() for state, value of WebSocket when value is @webSocket?.readyState
    null

  installEventHandlers: ->
    for eventName of @events
      handler = @events[eventName].bind(this)
      @webSocket["on#{eventName}"] = handler
    return

  uninstallEventHandlers: ->
    for eventName of @events
      @webSocket["on#{eventName}"] = ->
    return

  events:
    message: (event) ->
      {identifier, message, type} = JSON.parse(event.data)

      switch type
        when message_types.confirmation
          @consumer.subscriptions.notify(identifier, "connected")
        when message_types.rejection
          @consumer.subscriptions.reject(identifier)
        else
          @monitor.recordPing() if identifier == "_ping"
          @consumer.subscriptions.notify(identifier, "received", message)

    open: ->
      @disconnected = false
      @consumer.subscriptions.reload()

    open: ->
      Cable.log("WebSocket onopen event")
      @disconnected = false

    close: ->
      Cable.log("WebSocket onclose event")
      return if @disconnected
      @disconnected = true
      @monitor.recordDisconnect()
      @subscriptions.notifyAll("disconnected")

    error: ->
      Cable.log("WebSocket onerror event")

  toJSON: ->
    state: @getState()
