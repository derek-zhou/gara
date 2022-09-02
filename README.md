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
* A reduced subset of the markdown syntax is supported, so the messages can have a nice format

A typical use case is like this: You are in a social chatroom with many people, and you want to discuss something sensitive or only interesting to a smaller group of people. So you grab a room from Gara and post the link to the room. The people can opt-in to the smaller and safer chatroom by clicking the link. If one is done with it just leave the room. After the last one left, the room would be destroyed with all chat transcript lost.

## Message formating

Messages in Gara are formated with a simplified Markdown syntax. All simple formating control like bold, italic, strikethrough, etc. are supported. Hyperlinks and inline messages are also supported. Headings and tables are not supported. There are also a few extensions:

A sole URL would be expanded into a Open Graph link preview if possible. URLs as part of a messages are not expanded, nor would they be turned into a hyperlink. Please use Markdown's hyperlink syntax instead.

`#number` would be turned into a link to the numberred message in this chatroom. There should _not_ be any space in between the `#` and the number. There should be a space after the number.

`@nickname` would be highlighted, and the message would be turned into a private message that only the mentioned parties would receive. A private message can have multiple recipients. The server will not even keep a copy of a private message in the memory; so if the connection is dropped the private message would disapear.

## Private chatrooms

The topic string that you give does not need to be unique. Each time someone types a string, a new chatroom is generated. The only way to get in the same room is to get the link from someone already in the room. This way, the room is private to the party. The link to the room must be passed through some back channel that is outside Gara.

## Public chatrooms

It is also possible to make a public chatroom tied to one specific URL. Gara will detect if the topic string looks like an URL (any thing start with `https://`, doesn't need to be a real URL). If it does, then whoever type the exactly same URL later will join the same room. This way, there is no need to pass another URL through a back channel.

Gara will infer the URL if you click a link to the homepage of Gara from a web page, by looking the [referer header](https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Referer). Each unique URL in the world would get a dedicated chatroom with just a plain link. Isn't it neat?

One thing to keep in mind is you have to make sure the referer header is intact. In Firefox 87+ the default of referrer policy is very strict, it will strip off path and query string when crossing origins. So you may want to add the proper `referrerpolicy` attribute in the link, so visitors would not get lumped in one busy chatroom:

``` html
<a href="https://gara.fly.dev/" referrerpolicy="no-referrer-when-downgrade">Join the chat!</a>
```

Try it here: [Join the chat in Gara!](https://gara.fly.dev/)

If you use any path that is not used by the application itself, then it is also a public chatroom by the same name. So, a link to `https://gara.fly.dev/i/love/you/` is a public chatroom too.

Any public chatroom will be destroyed and recreated according to the same policy of a private chat room; we don't persist any data in the server-side. Also, a public chatroom can be more easily found out by trial and error, so be aware of the risk.

## Security considerations

The room link is randomly generated and is both unguessable and undiscoverable. The only way to get in is through someone giving you the link. So there should not be any intruders.

Users give no identity to the server. Like in a unregistered IRC, anyone can assume any nickname. Supposedly, the room link is only shared to people more or less know each other and have some level of trust to each other. Natually, people would not pretend to be someone else. And even if they did, it is very hard to establish credibility.

The only way to see the messages is through each participant's window. After the chat session ended, whatever left on the browser window is the only record one could have. The server does not keep any record. You could still get quoted out of context if someone took a screenshot though.

Although there is no end-to-end encryption, the connection between the user and the server is protected by SSL. The messages are only kept in memory, not persisted anywhere, so a leak is very unlikely. It is possible that someone can operate a rougue server that steal your chat messages though. So, if you have concerns you should only use a Gara server operated by someone you trust.

## Test instance

I encourage anyone technocally capable to operate their own Gara server. Gara is a standard [Phoenix Liveview](https://www.phoenixframework.org/) application that can be deployed anywhere. Even better, it does not need a database and has no persisted data. There is a couple of Dockerfiles in the source repository to faciliate deplyment. I have a deployment on [fly.io](https://fly.io) here: [gara.fly.dev](https://gara.fly.dev), and everyone is welcome to try. Please note this server will be taken offline from time to time, and it is on the free tier of fly.io, so it have a limited capacity.

To start your Phoenix server:

  * Install Elixir dependencies with `mix deps.get`
  * Install Javascript dependencies with `npm ci --prefix ./assets`
  * Start Phoenix endpoint with `mix phx.server` or inside IEx with `iex -S mix phx.server`

Now you can visit [`localhost:4000`](http://localhost:4000) from your browser.

If you want to deploy to fly.io like me, you should read fly.io's document [here](https://fly.io/docs/getting-started/elixir/) and familiar yourself with the process. In addition to the `SECRET_KEY_BASE` mentioned in the doc, Gara needs anther secret: `GUARDIAN_KEY` which is generated with: `mix guardian.gen.secret`. There is no database so you can skip over anything regarding database setup. 

Get a room when there is still one left and enjoy your private chat! If you have any suggestion, feel free to file an issue or send me a PR here.
