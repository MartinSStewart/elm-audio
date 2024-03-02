# elm-audio

This package explores the following question:

*What if we could play music and sound effects the same way we render HTML?*

To do that, elm-audio adds a `audio` field to your app. It looks something like this:
```elm
import Audio exposing (Audio, AudioData)
import Time

type alias Model = 
    { music : Audio.Source
    , musicStartTime : Time.Posix
    , soundOn : Bool
    }

audio : AudioData -> Model -> Audio
audio _ model =
    if model.soundOn then
        Audio.audio model.music model.musicStartTime
    else
        Audio.silence

{-
    Rest of the app...
-}

main = 
    Audio.elementWithAudio
        { init = init
        , update = update
        , view = view
        , subscriptions = subscriptions
        , audio = audio
        -- Since this is a normal Elm package we need ports to make this all work
        , audioPorts = audioPorts
        }
```

Notice that we don't need to write code to explicitly start and stop our music.
We just say what should be playing and when.
This is a lot like our view function, we don't say how our view should get updated, we just say what should appear.

## Getting Started

Make sure to install `ianmackenzie/elm-units` and `elm/time` as this package uses [`Duration`](https://package.elm-lang.org/packages/ianmackenzie/elm-units/latest/Duration#Duration) and [`Posix`](https://package.elm-lang.org/packages/elm/time/latest/Time#Posix).

Here is a simple [example app](https://ellie-app.com/nhNQDqZSNvha1) (source code is also [here](https://github.com/MartinSStewart/elm-audio/tree/master/example)) that's a good starting point if you want to begin making something with `elm-audio`.

If you want to see a more interesting use case, I rewrote the audio system in [elm-mogee](https://github.com/MartinSStewart/elm-mogee/tree/elm-audio) to use `elm-audio` (this uses an older version of elm-audio so the API won't exactly match).

## JS Setup

The following ports must be defined.

```elm
-- The ports must have these specific names.
port audioPortToJS : Json.Encode.Value -> Cmd msg
port audioPortFromJS : (Json.Decode.Value -> msg) -> Sub msg

main = 
    Audio.elementWithAudio
        { init = init
        , update = update
        , view = view
        , subscriptions = subscriptions
        , audio = audio
        , audioPort = { toJS = audioPortToJS, fromJS = audioPortFromJS }
        }
```

Then you'll need to copy the following JS code into your program and then call `startAudio(myElmApp);` (look at the [example app](https://github.com/MartinSStewart/elm-audio/blob/master/example/index.html) if you're not sure about this).

```javascript
function startAudio(r){if(window.AudioContext=window.AudioContext||window.webkitAudioContext||!1,window.AudioContext){let d=[],c=new AudioContext,i={};async function s(o){let e;try{var t=await fetch(o.audioUrl);e=await t.arrayBuffer()}catch{return void r.ports.audioPortFromJS.send({type:0,requestId:o.requestId,error:"NetworkError"})}try{var a=await c.decodeAudioData(e),n=d.length;d.push(a),r.ports.audioPortFromJS.send({type:1,requestId:o.requestId,bufferId:n,durationInSeconds:a.length/a.sampleRate})}catch(e){r.ports.audioPortFromJS.send({type:0,requestId:o.requestId,error:e.message})}}function m(e,o){return(e-o)/1e3+c.currentTime}function p(e,o){o?(e.loopStart=o.loopStart/1e3,e.loopEnd=o.loopEnd/1e3,e.loop=!0):e.loop=!1}function f(e,l){return e.map(o=>{var t,a,n=c.createGain(),r=(n.gain.setValueAtTime(o[0].volume,0),n.gain.linearRampToValueAtTime(o[0].volume,0),m(l,l));for(let e=1;e<o.length;e++){var d=o[e-1],i=m(d.time,l),s=o[e],u=m(s.time,l);r<u&&i<=r?(d=d.volume,t=s.volume,a=((a=r)-i)/(u-i),i=Number.isFinite(a)?a*(t-d)+d:d,n.gain.setValueAtTime(i,0),n.gain.linearRampToValueAtTime(s.volume,u)):r<u?n.gain.linearRampToValueAtTime(s.volume,u):n.gain.setValueAtTime(s.volume,0)}return n})}function v(o){for(let e=1;e<o.length;e++)o[e-1].connect(o[e])}r.ports.audioPortFromJS.send({type:2,samplesPerSecond:c.sampleRate}),r.ports.audioPortToJS.subscribe(async o=>{var t=(new Date).getTime();for(let e=0;e<o.audio.length;e++){var a=o.audio[e];switch(a.action){case"stopSound":var n=i[a.nodeGroupId];delete i[a.nodeGroupId],n.nodes.sourceNode.stop(),n.nodes.sourceNode.disconnect(),n.nodes.gainNode.disconnect(),n.nodes.volumeAtGainNodes.map(e=>e.disconnect());break;case"setVolume":i[a.nodeGroupId].nodes.gainNode.gain.setValueAtTime(a.volume,0);break;case"setVolumeAt":var n=i[a.nodeGroupId],r=(n.nodes.volumeAtGainNodes.map(e=>e.disconnect()),n.nodes.gainNode.disconnect(),f(a.volumeAt,t));v([n.nodes.gainNode,...r,c.destination]),n.nodes.volumeAtGainNodes=r;break;case"setLoopConfig":p(i[a.nodeGroupId].nodes.sourceNode,a.loop);break;case"setPlaybackRate":i[a.nodeGroupId].nodes.sourceNode.playbackRate.setValueAtTime(a.playbackRate,0);break;case"startSound":r=function(o,e,t,a,n,r,d,i){var s=c.createBufferSource();if(d){var u=10+d.loopEnd/1e3-o.length/o.sampleRate;if(0<u){var u=o.getChannelData(0).length+Math.ceil(u*o.sampleRate),l=c.createBuffer(o.numberOfChannels,u,c.sampleRate);for(let e=0;e<o.numberOfChannels;e++)l.copyToChannel(o.getChannelData(e),e);s.buffer=l}else s.buffer=o}else s.buffer=o;return s.playbackRate.value=i,p(s,d),u=f(t,r),(i=c.createGain()).gain.setValueAtTime(e,0),v([s,i,...u,c.destination]),r<=a?s.start(m(a,r),n/1e3):s.start(0,(r-a)/1e3+n/1e3),{sourceNode:s,gainNode:i,volumeAtGainNodes:u}}(d[a.bufferId],a.volume,a.volumeTimelines,a.startTime,a.startAt,t,a.loop,a.playbackRate);i[a.nodeGroupId]={bufferId:a.bufferId,nodes:r}}}var e=o.audioCmds.map(s);await Promise.all(e)})}else console.log("Web audio is not supported in your browser.")}
```
Unminified version can be found [here](https://github.com/MartinSStewart/elm-audio/blob/master/src/audio.js).