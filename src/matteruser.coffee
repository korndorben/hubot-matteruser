{Robot,Adapter,TextMessage,User,EnterMessage,LeaveMessage} = require 'hubot'

WebSocket = require 'ws'
MatterMostClient = require 'mattermost-client'

class Matteruser extends Adapter

    run: ->
        mmHost = process.env.MATTERMOST_HOST
        mmUser = process.env.MATTERMOST_USER
        mmPassword = process.env.MATTERMOST_PASSWORD
        mmGroup = process.env.MATTERMOST_GROUP
        mmWSSPort = process.env.MATTERMOST_WSS_PORT or '443'

        unless mmHost?
            @robot.logger.emergency "MATTERMOST_HOST is required"
            process.exit 1
        unless mmUser?
            @robot.logger.emergency "MATTERMOST_USER is required"
            process.exit 1
        unless mmPassword?
            @robot.logger.emergency "MATTERMOST_PASSWORD is required"
            process.exit 1
        unless mmGroup?
            @robot.logger.emergency "MATTERMOST_GROUP is required"
            process.exit 1

        @client = new MatterMostClient mmHost, mmGroup, mmUser, mmPassword, {wssPort: mmWSSPort}

        @client.on 'open', @.open
        @client.on 'loggedIn', @.loggedIn
        @client.on 'connected', @.onConnected
        @client.on 'message', @.message
        @client.on 'user_added', @.userAdded
        @client.on 'user_removed', @.userRemoved
        @client.on 'error', @.error
        @robot.brain.on 'loaded', @.brainLoaded

        @client.login()

    open: =>
        return true

    error: (err) =>
        @robot.logger.info 'Error: ' + err
        return true

    onConnected: =>
        @robot.logger.info 'Connected to Mattermost.'
        @emit 'connected'
        return true

    loggedIn: (user) =>
        @robot.logger.info 'Logged in as user "'+user.username+'" but not connected yet.'
        @self = user
        @robot.name = @self.username
        return true

    brainLoaded: =>
        @robot.logger.info 'Brain loaded'
        return true

    send: (envelope, strings...) ->
        @client.postMessage(str, envelope.room) for str in strings

    reply: (envelope, strings...) ->
        @robot.logger.debug "Reply"
        strings = strings.map (s) -> "@#{envelope.user.name} #{s}"
        @send envelope, strings...

    message: (msg) =>
        @robot.logger.debug msg
        return if msg.user_id == @self.id # Ignore our own output
        @robot.logger.debug 'From: ' + msg.user_id + ', To: ' + @self.id

        mmChannel = @client.getChannelByID msg.channel_id if msg.channel_id
        mmUser = @client.getUserByID msg.user_id
        mmPost = JSON.parse msg.props.post

        @robot.logger.debug 'Received message from '+mmUser.username+': ' + mmPost.message
        user = @robot.brain.userForId msg.user_id, name: mmUser.username, room: msg.channel_id

        text = mmPost.message
        text = "#{@robot.name} #{text}" if msg.props.channel_type == 'D' # Direct message

        @receive new TextMessage user, text, msg.id
        @robot.logger.debug "Message sent to hubot brain."
        return true

    userAdded: (msg) =>
        mmUser = @client.getUserByID msg.user_id
        user = @robot.brain.userForId msg.user_id, name: mmUser.username, room: msg.channel_id
        @receive new EnterMessage user
        return true

    userRemoved: (msg) =>
        mmUser = @client.getUserByID msg.user_id
        user = @robot.brain.userForId msg.user_id, name: mmUser.username, room: msg.channel_id
        @receive new LeaveMessage user
        return true

exports.use = (robot) ->
    new Matteruser robot
