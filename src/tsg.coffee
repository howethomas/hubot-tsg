{Adapter,TextMessage,Robot} = require '../../hubot'

url = require 'url'
http = require 'http'
express = require 'express'
Events = require 'events'
Emitter = Events.EventEmitter
Redis = require "redis"
Os = require("os")
Request = require('request')
ReadWriteLock = require('rwlock')
Util = require('util')
BodyParser = require('body-parser')
Multer = require('multer') 

class Tsg extends Adapter

  constructor: (robot) ->
    super(robot)
    @active_numbers = []
    @pending_tsg_requests = []

    @ee= new Emitter
    @robot = robot
    @secret= process.env.TSG_SECRET
    @THROTTLE_RATE_MS = 1500
    @TSG_SEND_MSG_URL = "http://sms.tsgglobal.com/jsonrpc"
    @TSG_UPDATE_NUMBER_URL = "http://rest.tsg.com/number/update"

    # Run a one second loop that checks to see if there are messages to be sent
    # to tsg. Wait one second after the request is made to avoid
    # rate throttling issues.
    setInterval(@drain_tsg, @THROTTLE_RATE_MS)


  report: (log_string) ->
    @robot.emit("log", log_string)

  drain_tsg: () =>
    request = @pending_tsg_requests.shift()
    if request?
      @report "Making request to #{request.url}"
      Request.post(
        request.options,
        (error, response, body) =>
          status_message = "Call to #{request.url} #{request.options.body.method}, #{JSON.stringify request.options.body.params}"
          if !error and response.statusCode == 200
            @report  status_message + " was successful."
          else
            @report  status_message + " failed with #{response.statusCode}:#{response.statusMessage}"
      )

  post_to_tsg: (options) =>
    request =
      url: options.url
      options: options
    @pending_tsg_requests.push request

  send_tsg_message: (to, from, text) =>
    options =
      url: @TSG_SEND_MSG_URL
      qs:
        key: @secret
      body:
        method: "sms.send"
        id: 0
        params: [from, to, text, 1]
      json: true
    @post_to_tsg(options)

  send: (envelope, strings...) =>
    {user, room} = envelope
    user = envelope if not user # pre-2.4.2 style
    from = user.room
    to = user.name
    @send_tsg_message(to, from, string) for string in strings

  emote: (envelope, strings...) =>
    @send envelope, "* #{str}" for str in strings

  reply: (envelope, strings...) =>
    strings = strings.map (s) -> "#{envelope.user.name}: #{s}"
    @send envelope, strings...

  run: ->
    self = @
    callback_path = process.env.TSG_CALLBACK_PATH or "/inbound/tsg"
    listen_port = process.env.TSG_LISTEN_PORT or 80
    routable_address = process.env.TSG_CALLBACK_URL or "127.0.0.1"

    callback_url = "#{routable_address}#{callback_path}"
    app = express()
    app.use(BodyParser.json())
    app.use(BodyParser.urlencoded({ extended: true }))
    app.use(Multer())

    app.post callback_path, (req, res) =>
      # First, see if this user is in the system.
      # If not, then let's make a new user for this far end.
      #
      res.writeHead 200,     "Content-Type": "text/plain"
      res.end()

      @report(req.body)
      if req.body.remote_number?
        user_name = user_id = req.body.remote_number.replace("+","")
        room_name = req.body.host_number.replace("+","")
        user = @robot.brain.userForId user_name, name: user_name, room: room_name
        inbound_message = new TextMessage user, req.body.message, 'message_id'
        @report "Received #{inbound_message} from #{user_name} bound for #{room_name}"
        @robot.receive inbound_message
        @report "Received #{inbound_message} from #{user_name} bound for #{room_name}"
        return



    server = app.listen(listen_port, =>
      host = server.address().address
      port = server.address().port
      @report "Tsg listening locally at http://%s:%s", host, port
      @report "External URL is #{callback_url}"
      return
    )

    @emit "connected"

    # Go through all of the active numbers, and add them.
    redis_client = Redis.createClient()
    redis_client.smembers("TSG_NUMBERS",
      (err, reply) =>
        @report "Not registering the following numbers: #{reply.join()}"
      )

exports.use = (robot) ->
  new Tsg robot
