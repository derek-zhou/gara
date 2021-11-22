# Gara, the chat room that leaves nothing behind

Get a room already! (Gara) is a web based chatroom that aims to be:

* private
* simple to use
* low maintainence

## Objectives

One may wonder why we need yet another chatroom, don't we have a bazilion of those already? If you look around, there are basically two types of chatrooms:

1. social networks run by big companies, ie: WhatsApp, Telegram, etc 
1. smaller networks silo'ed by organizations, ie: Slack, ...

The first type of chatrooms have questionable practice on user privacy, and the second type of chatrooms have limited reach. Gara is different:

* There is no login, everyone can hop on
* Each room is defined by a unique link to be shared
* Nothing is persisted anywhere, there is no database or third party service behind
* A reduced subset of the markdown syntax is supported, so the messages can have nice format

A typical usage is like this: You are in a social chatroom with many people, and you want to discuss something sensitive or only interesting to a smaller group of people. So you grab a room from Gara and post the link to the room. The people can opt-in to the smaller and safer chatroom by clicking the link. If one is done with it just leave the room. After the last one left, the room would be destroyed with all chat transcript lost.

## Security considerations

The room link is randomly generated and is both unguessable and undiscoverable. The only way to get in is through someone giving you the link. So there should not be any intruders.

Users give no identity to the server. Like in a unregistered IRC, anyone can assume any nickname. Supposedly, the room link is only shared to people more or less know each other and have some level of faith to each other. Natually, people would not pretend to be someone else. And even if they did, it is very hard to esteblish credibility.

The only way to see the messages is through each participants' window. After the chat session ended, whatever left on the browser window is the only record one could have. Being quoted out of context is of very limited dager here.

Although there is no end-to-end encryption, the connection between the user and the server is protected by SSL. The messages are only kept in memory, not persisted anywhere, so a leak is very unlikely. It is possible that someone can operate a rougue server that steal your chat messages though. So, if you have concerns you should only use a Gara server operated by someone you trust.

## Test instance

I encourage anyone technocally capable to operate their own Gara server. Gara is a standard [Phoenix Liveview](https://www.phoenixframework.org/) application that can be deployed anywhere. Even better, it does not need a database and has no persisted data. There is a couple of Dockerfile in the source repository to faciliate deplyment. I have a deployment on [fly.io](https://fly.io] here: [gara.fly.dev](https://gara.fly.dev), and everyone is welcome to try. Please note this server will be taken offline from time to time, and it is on the free tier of fly.io, so it have a limited capacity.

To start your Phoenix server:

  * Install Elixir dependencies with `mix deps.get`
  * Install Javascript dependencies with `npm ci --prefix ./assets`
  * Start Phoenix endpoint with `mix phx.server` or inside IEx with `iex -S mix phx.server`

Now you can visit [`localhost:4000`](http://localhost:4000) from your browser.

If you want to deploy to fly.io like me, you should read fly.io's document [here](https://fly.io/docs/getting-started/elixir/) and familiar yourself with the process. In addition to the `SECRET_KEY_BASE` mentioned in the doc, Gara needs anther secret: `GUARDIAN_KEY` which is generated with: `mix guardian.gen.secret`. There is no database so you can skip over anything regarding database setup. 

Get a room when there is one and enjoy your private chat! If you have any suggestion, feel free to file an issue or send me a PR here.
